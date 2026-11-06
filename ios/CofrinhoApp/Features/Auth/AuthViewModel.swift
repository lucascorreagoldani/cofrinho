import Foundation
import SwiftUI

/// View Model reativo com @Observable e @MainActor gerenciando o ciclo de vida de autenticação,
/// renovação silenciosa de sessão (Refresh Token de 7 dias) e verificação biométrica (Face ID / Touch ID).
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

    // Chaves de Persistência Local Segura (Keychain & UserDefaults)
    private let tokenKey = "cofrinho_jwt_token"
    private let refreshTokenKey = "cofrinho_refresh_token"
    private let sessionIdKey = "cofrinho_session_id"
    private let fastLoginKey = "cofrinho_fast_login_pref"
    private let biometryPrefKey = "cofrinho_biometry_pref"
    private let cachedUserKey = "cofrinho_cached_user_json"
    private let cachedPrefsKey = "cofrinho_cached_prefs_json"

    public init() {
        checkSavedSessionOnLaunch()
    }

    // MARK: - Ciclo de Abertura do App

    public func checkSavedSessionOnLaunch() {
        let isFastLoginEnabled = UserDefaults.standard.bool(forKey: fastLoginKey)
        guard isFastLoginEnabled else {
            return
        }

        // CRÍTICO: Para que a sessão seja renovável e válida na VPS, é OBRIGATÓRIO ter o Refresh Token de 7 dias.
        // Se NÃO temos o refresh token (ex: sessão expirada, antiga ou inconsistente), NUNCA solicita Face ID!
        // Limpa resquícios e exibe o formulário de login diretamente sem interrupções.
        guard let savedRefreshToken = KeychainHelper.shared.read(key: refreshTokenKey),
              !savedRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLogger.shared.info("Nenhuma sessão renovável encontrada. Exibindo tela de login diretamente (sem Face ID).", category: .security)
            performSilentLogout()
            return
        }

        // Se temos o refresh token, a sessão é válida! Carrega o cache local para UX imediata
        if let cachedUser = loadUserFromCache() {
            self.currentUser = cachedUser
            self.currentPreferences = loadPrefsFromCache()
        }

        self.token = KeychainHelper.shared.read(key: tokenKey)
        let isBiometryEnabled = UserDefaults.standard.bool(forKey: biometryPrefKey)

        Task {
            if isBiometryEnabled && BiometryService.shared.isBiometryAvailable {
                do {
                    let authenticated = try await BiometryService.shared.authenticate(
                        reason: "Desbloqueie o Cofrinho para acessar suas finanças."
                    )
                    if authenticated {
                        await validateOrRefreshSession()
                    }
                } catch let err as SecurityError {
                    self.activeError = err
                } catch {
                    self.activeError = SecurityError.authenticationFailed(reason: error.localizedDescription)
                }
            } else {
                await validateOrRefreshSession()
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

            // Persiste na Keychain e UserDefaults se "Manter Logado"
            if keepLoggedIn {
                KeychainHelper.shared.save(key: tokenKey, value: response.token)
                if let refToken = response.refreshToken {
                    KeychainHelper.shared.save(key: refreshTokenKey, value: refToken)
                }
                KeychainHelper.shared.save(key: sessionIdKey, value: response.session.id)
                UserDefaults.standard.set(true, forKey: fastLoginKey)

                saveUserToCache(response.user)
            } else {
                KeychainHelper.shared.clearAll()
                UserDefaults.standard.set(false, forKey: fastLoginKey)
            }

            // Busca preferências da nuvem
            let prefs = try? await AuthAPIService.shared.getPreferences(token: response.token)
            self.currentPreferences = prefs
            if let prefs {
                savePrefsToCache(prefs)
            }

            AppLogger.shared.info("Usuário \(response.user.username) autenticado na VPS com sucesso", category: .security)

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

            AppLogger.shared.info("Conta criada na VPS para \(trimmedUsername)", category: .app)

            // Realiza login imediato para obter os tokens e abrir a sessão
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

    public func logout() async {
        isLoading = true
        defer { isLoading = false }

        if let token {
            _ = try? await AuthAPIService.shared.logout(token: token)
        }

        performSilentLogout()
        self.passwordInput = ""
        self.registerPasswordInput = ""
        self.confirmPasswordInput = ""
    }

    // MARK: - Validação e Renovação Silenciosa de Sessão (Refresh Token)

    private func validateOrRefreshSession() async {
        guard let currentToken = token else {
            await tryRefreshToken()
            return
        }

        do {
            let profile = try await AuthAPIService.shared.getProfile(token: currentToken)
            let prefs = try? await AuthAPIService.shared.getPreferences(token: currentToken)
            self.currentUser = profile
            self.currentPreferences = prefs
            self.isAuthenticated = true

            saveUserToCache(profile)
            if let prefs { savePrefsToCache(prefs) }
        } catch let appErr as AuthError where appErr.errorCode == "AUTH_001" || appErr.errorCode == "AUTH_009" {
            // O access token expirou (15 minutos). Tenta renovar com o Refresh Token de 7 dias
            AppLogger.shared.info("Access token expirado, renovando sessão via Refresh Token na VPS...", category: .security)
            await tryRefreshToken()
        } catch let netErr as NetworkError {
            // Erro de conexão (offline, túnel etc): NUNCA desloga o usuário se tiver cache
            AppLogger.shared.warning("Falha temporária de rede (\(netErr.localizedDescription)). Mantendo sessão ativa com cache local.", category: .network)
            if self.currentUser != nil {
                self.isAuthenticated = true
            }
        } catch {
            AppLogger.shared.warning("Validação de sessão encontrou erro: \(error.localizedDescription). Tentando renovação.", category: .app)
            await tryRefreshToken()
        }
    }

    private func tryRefreshToken() async {
        guard let savedRefreshToken = KeychainHelper.shared.read(key: refreshTokenKey) else {
            AppLogger.shared.info("Nenhum refresh token encontrado. Requer novo login.", category: .security)
            performSilentLogout()
            return
        }

        do {
            let refreshResult = try await AuthAPIService.shared.refreshToken(refreshToken: savedRefreshToken)
            self.token = refreshResult.accessToken
            KeychainHelper.shared.save(key: tokenKey, value: refreshResult.accessToken)
            AppLogger.shared.info("Sessão renovada com sucesso na VPS via Refresh Token!", category: .security)

            // Obtém perfil atualizado com o novo token
            let profile = try await AuthAPIService.shared.getProfile(token: refreshResult.accessToken)
            let prefs = try? await AuthAPIService.shared.getPreferences(token: refreshResult.accessToken)
            self.currentUser = profile
            self.currentPreferences = prefs
            self.isAuthenticated = true

            saveUserToCache(profile)
            if let prefs { savePrefsToCache(prefs) }
        } catch let authErr as AuthError where authErr.errorCode == "AUTH_001" || authErr.errorCode == "AUTH_009" {
            // A sessão de 7 dias expirou de fato ou foi revogada no servidor
            AppLogger.shared.info("Sessão de 7 dias expirada na VPS. Solicitando novo login.", category: .security)
            performSilentLogout()
        } catch {
            // Se houver falha de rede temporária durante o refresh, não desconecta o usuário
            AppLogger.shared.warning("Falha de conexão com a VPS durante renovação de token. Mantendo autenticação offline.", category: .network)
            if self.currentUser != nil {
                self.isAuthenticated = true
            }
        }
    }

    private func performSilentLogout() {
        KeychainHelper.shared.clearAll()
        UserDefaults.standard.removeObject(forKey: fastLoginKey)
        UserDefaults.standard.removeObject(forKey: biometryPrefKey)
        self.token = nil
        self.currentUser = nil
        self.currentPreferences = nil
        self.isAuthenticated = false
    }

    // MARK: - Helpers de Cache Local (Offline & Instant Launch)

    private func saveUserToCache(_ user: UserProfileDTO) {
        if let data = try? JSONEncoder().encode(user),
           let json = String(data: data, encoding: .utf8) {
            KeychainHelper.shared.save(key: cachedUserKey, value: json)
        }
    }

    private func loadUserFromCache() -> UserProfileDTO? {
        guard let json = KeychainHelper.shared.read(key: cachedUserKey),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(UserProfileDTO.self, from: data)
    }

    private func savePrefsToCache(_ prefs: UserPreferencesDTO) {
        if let data = try? JSONEncoder().encode(prefs),
           let json = String(data: data, encoding: .utf8) {
            KeychainHelper.shared.save(key: cachedPrefsKey, value: json)
        }
    }

    private func loadPrefsFromCache() -> UserPreferencesDTO? {
        guard let json = KeychainHelper.shared.read(key: cachedPrefsKey),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(UserPreferencesDTO.self, from: data)
    }
}
