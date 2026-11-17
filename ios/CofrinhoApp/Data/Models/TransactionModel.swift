import Foundation
import SwiftUI

/// Relação embutida de categoria para visualização rápida no extrato
public struct CategoryRelationDTO: Codable, Sendable, Hashable {
    public let id: Int
    public let name: String
    public let icon: String
    public let color: String

    public init(id: Int, name: String, icon: String, color: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
    }
}

/// Relação embutida de conta para visualização rápida no extrato
public struct AccountRelationDTO: Codable, Sendable, Hashable {
    public let id: Int
    public let name: String
    public let type: String
    public let icon: String
    public let color: String

    public init(id: Int, name: String, type: String, icon: String, color: String) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.color = color
    }
}

/// DTO para sugestões inteligentes de autocompletar baseadas no histórico do usuário
public struct SuggestionItemDTO: Codable, Sendable, Identifiable, Hashable {
    public var id: String { description.lowercased() }
    public let description: String
    public let suggestedCategoryId: Int?
    public let suggestedAccountId: Int?
    public let count: Int

    enum CodingKeys: String, CodingKey {
        case description
        case suggestedCategoryId = "suggested_category_id"
        case suggestedAccountId = "suggested_account_id"
        case count
    }

    public init(description: String, suggestedCategoryId: Int? = nil, suggestedAccountId: Int? = nil, count: Int = 1) {
        self.description = Self.sanitizeDescription(description)
        self.suggestedCategoryId = suggestedCategoryId
        self.suggestedAccountId = suggestedAccountId
        self.count = count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawDescription = try container.decode(String.self, forKey: .description)
        self.description = Self.sanitizeDescription(rawDescription)
        self.suggestedCategoryId = try container.decodeIfPresent(Int.self, forKey: .suggestedCategoryId)
        self.suggestedAccountId = try container.decodeIfPresent(Int.self, forKey: .suggestedAccountId)
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
    }

    /// Remove sufixos de parcelamento `(1/2)`, `(2/10)` e quantidades `(2x)` / ` 2x` mantendo o nome limpo do estabelecimento/gasto.
    public static func sanitizeDescription(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            "\\s*\\(\\d+\\s*\\/\\s*\\d+\\)\\s*$",
            "\\s*\\(\\d+\\s*[xX]\\)\\s*$",
            "\\s+\\d+\\s*[xX]\\s*$"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }

        cleaned = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return cleaned.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }
}

/// Modelo de transação / gasto do Cofrinho.
/// Armazena valores monetários com alta precisão e timestamps numéricos (epoch ms).
public struct TransactionModel: Identifiable, Codable, Sendable, Hashable {
    public let id: Int
    public let userId: Int
    public var categoryId: Int
    public var category: CategoryRelationDTO?
    public var accountId: Int
    public var account: AccountRelationDTO?
    public var type: String
    public var amount: Decimal
    public var description: String
    public var notes: String?
    public var date: Int
    public var hasTime: Bool
    public var status: String
    public var isInstallment: Bool
    public var installmentNumber: Int?
    public var totalInstallments: Int?
    public var installmentGroupId: String?
    public let createdAt: Int
    public let updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case categoryId = "category_id"
        case category
        case accountId = "account_id"
        case account
        case type
        case amount
        case description
        case notes
        case date
        case hasTime = "has_time"
        case status
        case isInstallment = "is_installment"
        case installmentNumber = "installment_number"
        case totalInstallments = "total_installments"
        case installmentGroupId = "installment_group_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: Int,
        userId: Int,
        categoryId: Int,
        category: CategoryRelationDTO? = nil,
        accountId: Int,
        account: AccountRelationDTO? = nil,
        type: String = "expense",
        amount: Decimal,
        description: String,
        notes: String? = nil,
        date: Int = Int(Date().timeIntervalSince1970 * 1000),
        hasTime: Bool = false,
        status: String = "active",
        isInstallment: Bool = false,
        installmentNumber: Int? = nil,
        totalInstallments: Int? = nil,
        installmentGroupId: String? = nil,
        createdAt: Int = Int(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int = Int(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.userId = userId
        self.categoryId = categoryId
        self.category = category
        self.accountId = accountId
        self.account = account
        self.type = type
        self.amount = amount
        self.description = description
        self.notes = notes
        self.date = date
        self.hasTime = hasTime
        self.status = status
        self.isInstallment = isInstallment
        self.installmentNumber = installmentNumber
        self.totalInstallments = totalInstallments
        self.installmentGroupId = installmentGroupId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.userId = try container.decode(Int.self, forKey: .userId)
        self.categoryId = try container.decode(Int.self, forKey: .categoryId)
        self.category = try container.decodeIfPresent(CategoryRelationDTO.self, forKey: .category)
        self.accountId = try container.decode(Int.self, forKey: .accountId)
        self.account = try container.decodeIfPresent(AccountRelationDTO.self, forKey: .account)
        self.type = try container.decode(String.self, forKey: .type)

        // Suporta decodificação tanto de Double numérico quanto de String para Decimal
        if let doubleVal = try? container.decode(Double.self, forKey: .amount) {
            self.amount = Decimal(doubleVal)
        } else if let stringVal = try? container.decode(String.self, forKey: .amount), let dec = Decimal(string: stringVal) {
            self.amount = dec
        } else {
            self.amount = try container.decode(Decimal.self, forKey: .amount)
        }

        self.description = try container.decode(String.self, forKey: .description)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.date = try container.decode(Int.self, forKey: .date)
        self.hasTime = try container.decode(Bool.self, forKey: .hasTime)
        self.status = try container.decode(String.self, forKey: .status)
        self.isInstallment = try container.decode(Bool.self, forKey: .isInstallment)
        self.installmentNumber = try container.decodeIfPresent(Int.self, forKey: .installmentNumber)
        self.totalInstallments = try container.decodeIfPresent(Int.self, forKey: .totalInstallments)
        self.installmentGroupId = try container.decodeIfPresent(String.self, forKey: .installmentGroupId)
        self.createdAt = try container.decode(Int.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Int.self, forKey: .updatedAt)
    }

    /// Status tipado via Enum canônico
    public var statusEnum: RecordStatus {
        RecordStatus(rawValue: status) ?? .active
    }

    /// Tipo tipado via Enum canônico
    public var typeEnum: TransactionType {
        TransactionType(rawValue: type) ?? .expense
    }

    /// Objeto Date correspondente ao timestamp numérico em epoch ms.
    public var dateValue: Date {
        Date(timeIntervalSince1970: TimeInterval(date) / 1000.0)
    }

    /// Formatação monetária padronizada em Real (R$ 0,00) via FormatStyle nativo.
    public var formattedAmount: String {
        amount.brlCurrencyFormatted
    }

    /// Data formatada amigável (DD/MM/AAAA) via FormatStyle nativo.
    public var formattedDate: String {
        dateValue.brShortDateFormatted
    }

    /// Identificador visual da parcela (ex: "1/10")
    public var installmentBadge: String? {
        guard isInstallment, let num = installmentNumber, let total = totalInstallments else {
            return nil
        }
        return "\(num)/\(total)"
    }
}

