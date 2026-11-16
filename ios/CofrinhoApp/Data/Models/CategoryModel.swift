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

    /// Status tipado via Enum canônico
    public var statusEnum: RecordStatus {
        RecordStatus(rawValue: status) ?? .active
    }

    /// Cor nativa SwiftUI calculada a partir do hexadecimal armazenado no PostgreSQL.
    public var swiftUIColor: Color {
        Color(hex: color, defaultColor: .orange)
    }
}

