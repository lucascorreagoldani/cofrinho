import Foundation
import SwiftUI

/// View Model reativo com @Observable e @MainActor gerenciando o ciclo de vida de autenticação,
/// sessões seguras e verificação biométrica (Face ID / Touch ID).
@Observable
@MainActor
public final class AuthViewModel {
    // MARK: - Estado de Autenticação
    public var isAuthenticated: Bool = false
    public var currentUser: UserProfileDTO?
    public var currentPreferences: UserPreferencesDTO?
    public var token: String?

    // MARK: - Modos e Formulários
    public var isRegistering: Bool = false

    // Campos de Login
    public var loginInput: String = ""
    public var passwordInput: String = ""
    public var keepLoggedIn: Bool = true

    // Campos de Cadastro
    public var usernameInput: String = ""
    public var emailInput: String = ""
    public var registerPasswordInput: String = ""
    public var confirmPasswordInput: String = ""

    // MARK: - Estados de UI e Controle
    public var isLoading: Bool = false
    public var activeError: (any AppErrorProtocol)?
    public var showBiometryPromptDialog: Bool = false

    // Chaves de Persistência Local
    private let tokenKey = "cofrinho_jwt_token"
    private let sessionIdKey = "cofrinho_session_id"
    private let fastLoginKey = "cofrinho_fast_login_pref"
    private let biometryPrefKey = "cofrinho_biometry_pref"

    public init() {
        checkSavedSessionOnLaunch()
    }

    // MARK: - Ciclo de Abertura do App

    public func checkSavedSessionOnLaunch() {
        guard let savedToken = KeychainHelper.shared.read(key: tokenKey) else {
            return
        }

        let isFastLoginEnabled = UserDefaults.standard.bool(forKey: fastLoginKey)
        guard isFastLoginEnabled else {
            KeychainHelper.shared.clearAll()
            return
        }

        self.token = savedToken
        let isBiometryEnabled = UserDefaults.standard.bool(forKey: biometryPrefKey)

        Task {
            if isBiometryEnabled && BiometryService.shared.isBiometryAvailable {
                do {
                    let authenticated = try await BiometryService.shared.authenticate(
                        reason: "Desbloqueie o Cofrinho para acessar suas finanças."
                    )
                    if authenticated {
                        await loadUserData(token: savedToken)
                    }
                } catch let err as SecurityError {
                    self.activeError = err
                } catch {
                    self.activeError = SecurityError.authenticationFailed(reason: error.localizedDescription)
                }
            } else {
                await loadUserData(token: savedToken)
            }
        }
    }

    // MARK: - Ações de Autenticação

    public func login() async {
        let trimmedLogin = loginInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty, !passwordInput.isEmpty else {
            activeError = AuthError.emptyFields
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await AuthAPIService.shared.login(
                login: trimmedLogin,
                password: passwordInput,
                fastLogin: keepLoggedIn
            )

            self.token = response.token
            self.currentUser = response.user

            // Persiste na Keychain se "Manter Logado"
            if keepLoggedIn {
                KeychainHelper.shared.save(key: tokenKey, value: response.token)
                KeychainHelper.shared.save(key: sessionIdKey, value: response.session.id)
                UserDefaults.standard.set(true, forKey: fastLoginKey)
            } else {
                KeychainHelper.shared.clearAll()
                UserDefaults.standard.set(false, forKey: fastLoginKey)
            }

            // Busca preferências
            let prefs = try? await AuthAPIService.shared.getPreferences(token: response.token)
            self.currentPreferences = prefs

            AppLogger.shared.info("Usuário \(response.user.username) autenticado com sucesso", category: .security)

            // Se o aparelho suporta Face ID/Touch ID e ainda não configurou, sugere ativar
            if BiometryService.shared.isBiometryAvailable && !(prefs?.verification ?? false) {
                self.showBiometryPromptDialog = true
            } else {
                self.isAuthenticated = true
            }
        } catch let appErr as any AppErrorProtocol {
            self.activeError = appErr
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }

    public func register() async {
        let trimmedUsername = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUsername.isEmpty, !trimmedEmail.isEmpty, !registerPasswordInput.isEmpty, !confirmPasswordInput.isEmpty else {
            activeError = AuthError.emptyFields
            return
        }

        guard trimmedUsername.count >= 3 else {
            activeError = AuthError.usernameTooShort
            return
        }

        guard isValidEmail(trimmedEmail) else {
            activeError = AuthError.invalidEmailFormat
            return
        }

        guard registerPasswordInput.count >= 8 else {
            activeError = AuthError.passwordTooShort
            return
        }

        let hasUppercase = registerPasswordInput.contains(where: { $0.isUppercase })
        let hasNumber = registerPasswordInput.contains(where: { $0.isNumber })
        guard hasUppercase && hasNumber else {
            activeError = AuthError.passwordRequiresComplexity
            return
        }

        guard registerPasswordInput == confirmPasswordInput else {
            activeError = AuthError.passwordsDoNotMatch
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await AuthAPIService.shared.register(
                username: trimmedUsername,
                email: trimmedEmail,
                password: registerPasswordInput
            )

            AppLogger.shared.info("Conta criada com sucesso para \(trimmedUsername)", category: .app)

            // Realiza login imediato
            self.loginInput = trimmedUsername
            self.passwordInput = registerPasswordInput
            await login()
        } catch let appErr as any AppErrorProtocol {
            self.activeError = appErr
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: email)
    }

    public func confirmBiometryChoice(enable: Bool) async {
        showBiometryPromptDialog = false

        if enable {
            do {
                let success = try await BiometryService.shared.authenticate(
                    reason: "Confirme seu \(BiometryService.shared.biometryName) para habilitar o login rápido."
                )
                if success {
                    UserDefaults.standard.set(true, forKey: biometryPrefKey)
                    if let token {
                        _ = try? await AuthAPIService.shared.updatePreferences(token: token, verification: true)
                    }
                    currentPreferences?.verification = true
                }
            } catch {
                UserDefaults.standard.set(false, forKey: biometryPrefKey)
            }
        } else {
            UserDefaults.standard.set(false, forKey: biometryPrefKey)
            if let token {
                _ = try? await AuthAPIService.shared.updatePreferences(token: token, verification: false)
            }
            currentPreferences?.verification = false
        }

        self.isAuthenticated = true
    }

    public func toggleBiometryInSettings(enable: Bool) async {
        if enable {
            do {
                let success = try await BiometryService.shared.authenticate(
                    reason: "Confirme seu \(BiometryService.shared.biometryName) para ativar a proteção biométrica."
                )
                if success {
                    UserDefaults.standard.set(true, forKey: biometryPrefKey)
                    if let token {
                        _ = try? await AuthAPIService.shared.updatePreferences(token: token, verification: true)
                    }
                    currentPreferences?.verification = true
                }
            } catch let err as SecurityError {
                self.activeError = err
            } catch {
                self.activeError = SecurityError.authenticationFailed(reason: error.localizedDescription)
            }
        } else {
            UserDefaults.standard.set(false, forKey: biometryPrefKey)
            if let token {
                _ = try? await AuthAPIService.shared.updatePreferences(token: token, verification: false)
            }
            currentPreferences?.verification = false
        }
    }

    public func loginOfflineMode() {
        let chosenName = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (loginInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "lucas" : loginInput)
            : usernameInput

        let chosenEmail = emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(chosenName)@cofrinho.app"
            : emailInput

        let nowMs = Int(Date().timeIntervalSince1970 * 1000)

        let fallbackUser = UserProfileDTO(
            id: 1,
            username: chosenName,
            email: chosenEmail,
            firstIp: "127.0.0.1",
            lastIp: "127.0.0.1",
            firstLogin: nowMs,
            lastLogin: nowMs,
            registeredAt: nowMs
        )

        self.currentUser = fallbackUser
        self.currentPreferences = UserPreferencesDTO(
            userId: 1,
            fastLogin: keepLoggedIn,
            verification: false,
            updatedAt: nowMs
        )

        if keepLoggedIn {
            UserDefaults.standard.set(true, forKey: fastLoginKey)
        }

        self.activeError = nil
        self.isAuthenticated = true
        AppLogger.shared.info("Entrando no Modo Offline com dados locais para \(chosenName)", category: .app)
    }

    public func logout() async {
        isLoading = true
        defer { isLoading = false }

        if let token {
            _ = try? await AuthAPIService.shared.logout(token: token)
        }

        KeychainHelper.shared.clearAll()
        UserDefaults.standard.removeObject(forKey: fastLoginKey)
        UserDefaults.standard.removeObject(forKey: biometryPrefKey)

        self.token = nil
        self.currentUser = nil
        self.currentPreferences = nil
        self.isAuthenticated = false
        self.passwordInput = ""
        self.registerPasswordInput = ""
        self.confirmPasswordInput = ""
    }

    // MARK: - Carregamento de Perfil

    private func loadUserData(token: String) async {
        do {
            let profile = try await AuthAPIService.shared.getProfile(token: token)
            let prefs = try? await AuthAPIService.shared.getPreferences(token: token)
            self.currentUser = profile
            self.currentPreferences = prefs
            self.isAuthenticated = true
        } catch {
            // Se o token estiver expirado na API
            KeychainHelper.shared.clearAll()
            self.token = nil
            self.isAuthenticated = false
        }
    }
}
