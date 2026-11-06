import SwiftUI

/// Modelo de categoria de transação no Cofrinho.
/// Totalmente compatível com Swift 6 e estritamente tipado.
public struct CategoryModel: Identifiable, Codable, Sendable, Hashable {
    public let id: Int
    public let userId: Int
    public var name: String
    public var icon: String
    public var color: String
    public let isDefault: Bool
    public var status: String
    public let createdAt: Int
    public let updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case icon
        case color
        case isDefault = "is_default"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: Int,
        userId: Int,
        name: String,
        icon: String = "tag.fill",
        color: String = "#FF9500",
        isDefault: Bool = false,
        status: String = "active",
        createdAt: Int = Int(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int = Int(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.icon = icon
        self.color = color
        self.isDefault = isDefault
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Cor nativa SwiftUI calculada a partir do hexadecimal armazenado no PostgreSQL.
    public var swiftUIColor: Color {
        let hex = color.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return Color.orange
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

