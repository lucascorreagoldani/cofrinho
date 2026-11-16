import Foundation

/// Status canônico de visibilidade e ciclo de vida de registros no Cofrinho.
public enum RecordStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active = "active"
    case hidden = "hidden"
    case deleted = "deleted"

    public var id: String { rawValue }
}

/// Opções de filtro de visibilidade no Extrato de transações.
public enum TransactionFilterStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active = "active"
    case all = "all"
    case hidden = "hidden"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .active: return "Ativas"
        case .all: return "Todas (com ocultas)"
        case .hidden: return "Apenas Ocultas"
        }
    }
}

/// Tipos de movimentação financeira suportados pela API.
public enum TransactionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense = "expense"
    case income = "income"

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .expense: return "Gasto"
        case .income: return "Receita"
        }
    }
}

/// Tipos de conta, carteira ou cartão de pagamento cadastráveis pelo usuário.
public enum AccountType: String, Codable, CaseIterable, Identifiable, Sendable {
    case creditCard = "credit_card"
    case pix = "pix"
    case bankAccount = "bank_account"
    case wallet = "wallet"
    case cash = "cash"

    public var id: String { rawValue }

    /// Nome completo legível para exibição em menus, detalhes e badges.
    public var localizedName: String {
        switch self {
        case .creditCard: return "Cartão de Crédito"
        case .pix: return "PIX"
        case .bankAccount: return "Conta Bancária"
        case .wallet: return "Carteira Digital"
        case .cash: return "Dinheiro"
        }
    }

    /// Título compacto ideal para controles segmentados.
    public var shortTitle: String {
        switch self {
        case .creditCard: return "Cartão"
        case .pix: return "PIX"
        case .bankAccount: return "Conta"
        case .wallet: return "Carteira"
        case .cash: return "Dinheiro"
        }
    }

    /// SF Symbol padrão associado a cada tipo de conta.
    public var defaultIcon: String {
        switch self {
        case .creditCard: return "creditcard.fill"
        case .pix: return "bolt.horizontal.fill"
        case .bankAccount: return "building.columns.fill"
        case .wallet: return "wallet.pass.fill"
        case .cash: return "banknote.fill"
        }
    }

    /// Indica se o tipo de conta aceita parcelamento por padrão ao criar.
    public var supportsInstallmentsByDefault: Bool {
        self == .creditCard
    }
}

/// Modos de exclusão em cascata para transações parceladas.
public enum DeleteCascadeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case single = "single"
    case allFuture = "all_future"

    public var id: String { rawValue }
}

/// Estado de sincronização offline no cache local SwiftData.
public enum SyncStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case synced = "synced"
    case pendingCreate = "pending_create"
    case pendingUpdate = "pending_update"
    case pendingDelete = "pending_delete"

    public var id: String { rawValue }
}
