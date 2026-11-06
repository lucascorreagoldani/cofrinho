import Foundation

/// Erros de validação de regras de negócio em formulários e entradas de dados.
public enum ValidationError: AppErrorProtocol {
    case invalidAmount
    case emptyTitle
    case futureDateNotAllowed
    case invalidGoalTarget
    case custom(message: String)

    public var errorCode: String {
        switch self {
        case .invalidAmount: return "VAL_001"
        case .emptyTitle: return "VAL_002"
        case .futureDateNotAllowed: return "VAL_003"
        case .invalidGoalTarget: return "VAL_004"
        case .custom: return "VAL_999"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "O valor informado deve ser maior do que zero."
        case .emptyTitle:
            return "O título ou descrição não pode estar em branco."
        case .futureDateNotAllowed:
            return "A data selecionada não pode estar no futuro."
        case .invalidGoalTarget:
            return "A meta de economia precisa ter um valor alvo positivo."
        case .custom(let message):
            return message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidAmount:
            return "Digite um valor numérico válido para registrar a transação."
        case .emptyTitle:
            return "Preencha um nome para identificar esta transação ou meta."
        case .futureDateNotAllowed:
            return "Selecione a data de hoje ou uma data passada."
        case .invalidGoalTarget:
            return "Defina quanto você deseja poupar para essa meta."
        case .custom:
            return "Corrija os dados informados e tente novamente."
        }
    }

    public var debugDetails: String? {
        switch self {
        case .invalidAmount:
            return "[VAL_001] Quantia informada menor ou igual a zero"
        case .emptyTitle:
            return "[VAL_002] Campo de texto obrigatório vazio"
        case .futureDateNotAllowed:
            return "[VAL_003] Violação de data máxima permitida"
        case .invalidGoalTarget:
            return "[VAL_004] Alvo financeiro inválido"
        case .custom(let msg):
            return "[VAL_999] Validação customizada falhou: \(msg)"
        }
    }
}

