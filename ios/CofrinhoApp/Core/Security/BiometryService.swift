import Foundation
import LocalAuthentication

/// Serviço responsável pelo gerenciamento e verificação de biometria (Face ID e Touch ID).
public final class BiometryService: @unchecked Sendable {
    public static let shared = BiometryService()

    private init() {}

    /// Tipo de biometria suportado pelo dispositivo.
    public var biometryType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        return context.biometryType
    }

    /// Nome legível do tipo de biometria disponível no dispositivo (ex: "Face ID" ou "Touch ID").
    public var biometryName: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Biometria"
        }
    }

    /// Ícone SF Symbol apropriado para a biometria disponível.
    public var biometryIconName: String {
        switch biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        default:
            return "lock.shield.fill"
        }
    }

    /// Verifica se o dispositivo possui hardware e biometria configurados.
    public var isBiometryAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Executa o prompt nativo de autenticação biométrica do iOS.
    public func authenticate(reason: String = "Confirme sua identidade para acessar o Cofrinho.") async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            AppLogger.shared.warning("Biometria indisponível no dispositivo", category: .security)
            throw SecurityError.biometryNotAvailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            if success {
                AppLogger.shared.info("Autenticação biométrica validada com sucesso", category: .security)
                return true
            } else {
                throw SecurityError.authenticationFailed(reason: "Validação biométrica recusada")
            }
        } catch let laError as LAError {
            AppLogger.shared.warning("Falha na autenticação biométrica: \(laError.localizedDescription)", category: .security)
            switch laError.code {
            case .userCancel, .appCancel:
                return false
            case .biometryNotEnrolled:
                throw SecurityError.biometryNotEnrolled
            case .biometryLockout:
                throw SecurityError.biometryLockout
            default:
                throw SecurityError.authenticationFailed(reason: laError.localizedDescription)
            }
        } catch {
            throw SecurityError.authenticationFailed(reason: error.localizedDescription)
        }
    }
}
