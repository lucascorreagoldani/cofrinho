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

    /// Título legível do tipo de conta
    public var friendlyTypeName: String {
        switch type {
        case "credit_card": return "Cartão de Crédito"
        case "pix": return "PIX"
        case "cash": return "Dinheiro"
        case "wallet": return "Carteira Digital"
        case "bank_account": return "Conta Bancária"
        default: return "Conta"
        }
    }

    /// Cor nativa SwiftUI calculada a partir do hexadecimal
    public var swiftUIColor: Color {
        let hex = color.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return Color.blue
        }
        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

