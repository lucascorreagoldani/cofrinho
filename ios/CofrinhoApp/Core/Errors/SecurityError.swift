import Foundation

/// Erros relacionados à segurança, biometria (Face ID / Touch ID) e acesso local.
public enum SecurityError: AppErrorProtocol {
    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockout
    case userCancelled
    case authenticationFailed(reason: String)

    public var errorCode: String {
        switch self {
        case .biometryNotAvailable: return "SEC_001"
        case .biometryNotEnrolled: return "SEC_002"
        case .biometryLockout: return "SEC_003"
        case .userCancelled: return "SEC_004"
        case .authenticationFailed: return "SEC_005"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .biometryNotAvailable:
            return "O Face ID / Touch ID não está disponível neste dispositivo."
        case .biometryNotEnrolled:
            return "Nenhuma biometria cadastrada no dispositivo."
        case .biometryLockout:
            return "O Face ID / Touch ID foi bloqueado após muitas tentativas."
        case .userCancelled:
            return "A autenticação foi cancelada."
        case .authenticationFailed:
            return "Não foi possível validar sua identidade."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .biometryNotAvailable:
            return "Você pode utilizar o código de acesso do dispositivo para desbloquear."
        case .biometryNotEnrolled:
            return "Cadastre o Face ID ou Touch ID nos Ajustes do seu iPhone."
        case .biometryLockout:
            return "Bloqueie e desbloqueie o dispositivo usando a senha para reativar a biometria."
        case .userCancelled:
            return "Toque no botão de autenticação para tentar novamente."
        case .authenticationFailed:
            return "Tente novamente posicionando seu rosto ou digital com clareza."
        }
    }

    public var debugDetails: String? {
        switch self {
        case .biometryNotAvailable:
            return "[SEC_001] LAError.biometryNotAvailable"
        case .biometryNotEnrolled:
            return "[SEC_002] LAError.biometryNotEnrolled"
        case .biometryLockout:
            return "[SEC_003] LAError.biometryLockout"
        case .userCancelled:
            return "[SEC_004] LAError.userCancel"
        case .authenticationFailed(let reason):
            return "[SEC_005] Falha de validação biométrica: \(reason)"
        }
    }
}

