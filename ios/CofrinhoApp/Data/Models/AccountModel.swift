import SwiftUI

/// Modelo de conta/carteira/cartão de pagamento do usuário no Cofrinho.
/// Suporta contas à vista (PIX, Débito, Dinheiro) e cartões com parcelamento e datas de fatura.
public struct AccountModel: Identifiable, Codable, Sendable, Hashable {
    public let id: Int
    public let userId: Int
    public var name: String
    public var type: String
    public var icon: String
    public var color: String
    public var allowsInstallments: Bool
    public var closingDay: Int?
    public var dueDay: Int?
    public var status: String
    public let createdAt: Int
    public let updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case type
        case icon
        case color
        case allowsInstallments = "allows_installments"
        case closingDay = "closing_day"
        case dueDay = "due_day"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: Int,
        userId: Int,
        name: String,
        type: String = "credit_card",
        icon: String = "creditcard.fill",
        color: String = "#0A84FF",
        allowsInstallments: Bool = true,
        closingDay: Int? = 20,
        dueDay: Int? = 27,
        status: String = "active",
        createdAt: Int = Int(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int = Int(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.icon = icon
        self.color = color
        self.allowsInstallments = allowsInstallments
        self.closingDay = closingDay
        self.dueDay = dueDay
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Tipo da conta mapeado via Enum canônico
    public var accountTypeEnum: AccountType {
        AccountType(rawValue: type) ?? .bankAccount
    }

    /// Status tipado via Enum canônico
    public var statusEnum: RecordStatus {
        RecordStatus(rawValue: status) ?? .active
    }

    /// Título legível do tipo de conta
    public var friendlyTypeName: String {
        AccountType(rawValue: type)?.localizedName ?? "Conta"
    }

    /// Cor nativa SwiftUI calculada a partir do hexadecimal
    public var swiftUIColor: Color {
        Color(hex: color, defaultColor: .blue)
    }
}

