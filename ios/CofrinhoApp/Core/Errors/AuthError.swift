import Foundation

/// Erros tipados e amigáveis relacionados aos fluxos de autenticação, cadastro e sessões.
public enum AuthError: AppErrorProtocol {
    case invalidCredentials
    case emptyFields
    case usernameTooShort
    case invalidEmailFormat
    case passwordTooShort
    case passwordRequiresComplexity
    case passwordsDoNotMatch
    case accountAlreadyExists(detail: String)
    case unauthorized
    case serverError(message: String, incidentId: String? = nil)

    public var errorCode: String {
        switch self {
        case .invalidCredentials: return "AUTH_001"
        case .emptyFields: return "AUTH_002"
        case .usernameTooShort: return "AUTH_003"
        case .invalidEmailFormat: return "AUTH_004"
        case .passwordTooShort: return "AUTH_005"
        case .passwordRequiresComplexity: return "AUTH_006"
        case .passwordsDoNotMatch: return "AUTH_007"
        case .accountAlreadyExists: return "AUTH_008"
        case .unauthorized: return "AUTH_009"
        case .serverError: return "AUTH_500"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Usuário/e-mail ou senha incorretos."
        case .emptyFields:
            return "Por favor, preencha todos os campos obrigatórios."
        case .usernameTooShort:
            return "O nome de usuário deve conter no mínimo 3 caracteres."
        case .invalidEmailFormat:
            return "Por favor, insira um endereço de e-mail válido (ex: seu@email.com)."
        case .passwordTooShort:
            return "A senha deve conter no mínimo 8 caracteres."
        case .passwordRequiresComplexity:
            return "A senha precisa conter pelo menos uma letra maiúscula e um número."
        case .passwordsDoNotMatch:
            return "A confirmação de senha não coincide com a senha digitada."
        case .accountAlreadyExists(let detail):
            return detail.isEmpty ? "Já existe uma conta cadastrada com estes dados." : detail
        case .unauthorized:
            return "Sessão expirada ou não autorizada. Faça login novamente."
        case .serverError(let message, let incidentId):
            if let incidentId, !incidentId.isEmpty {
                return "\(message)\n(Protocolo: \(incidentId))"
            }
            return message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidCredentials:
            return "Verifique se digitou o login e a senha corretamente e tente de novo."
        case .emptyFields:
            return "Complete todas as informações solicitadas no formulário."
        case .usernameTooShort:
            return "Escolha um nome de usuário com 3 ou mais letras ou números."
        case .invalidEmailFormat:
            return "Verifique se o e-mail possui '@' e um domínio válido."
        case .passwordTooShort, .passwordRequiresComplexity:
            return "Crie uma senha forte com pelo menos 8 dígitos, contendo letras maiúsculas e números."
        case .passwordsDoNotMatch:
            return "Certifique-se de digitar a mesma senha nos dois campos."
        case .accountAlreadyExists:
            return "Caso já possua cadastro, utilize a opção 'Fazer Login' com suas credenciais."
        case .unauthorized:
            return "Entre novamente com seu login e senha para revalidar seu acesso."
        case .serverError(_, let incidentId):
            if let incidentId {
                return "Se o problema persistir, informe o protocolo \(incidentId) ao suporte."
            }
            return "Tente novamente em instantes."
        }
    }

    public var debugDetails: String? {
        switch self {
        case .invalidCredentials:
            return "[AUTH_001] Falha de autenticação: credenciais inválidas"
        case .emptyFields:
            return "[AUTH_002] Campos obrigatórios não preenchidos"
        case .usernameTooShort:
            return "[AUTH_003] Nome de usuário com menos de 3 caracteres"
        case .invalidEmailFormat:
            return "[AUTH_004] Formato de e-mail inválido"
        case .passwordTooShort:
            return "[AUTH_005] Senha menor que 8 caracteres"
        case .passwordRequiresComplexity:
            return "[AUTH_006] Senha não atende aos requisitos de complexidade"
        case .passwordsDoNotMatch:
            return "[AUTH_007] Divergência entre senha e confirmação"
        case .accountAlreadyExists(let detail):
            return "[AUTH_008] Conflito de recurso único: \(detail)"
        case .unauthorized:
            return "[AUTH_009] Token JWT inválido, ausente ou expirado"
        case .serverError(let message, let incidentId):
            return "[AUTH_500] Erro retornado pela API: \(message) - Incident: \(incidentId ?? "N/A")"
        }
    }
}

