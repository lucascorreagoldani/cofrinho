import Foundation
import SwiftData

/// Entidade local do SwiftData para persistência offline de transações e gastos.
@Model
public final class LocalTransaction {
    @Attribute(.unique) public var localId: String
    public var serverId: Int?
    public var userId: Int
    public var categoryId: Int
    public var accountId: Int
    public var type: String
    public var amount: Double
    public var transactionDescription: String
    public var date: Int // Unix epoch ms
    public var hasTime: Bool
    public var status: String // active, hidden, deleted
    public var isInstallment: Bool
    public var installmentNumber: Int?
    public var totalInstallments: Int?
    public var installmentGroupId: String?
    public var createdAt: Int
    public var updatedAt: Int
    public var syncStatus: String // synced, pending_create, pending_update, pending_delete

    // Metadados cacheados de categoria e conta para exibição offline instantânea
    public var categoryName: String?
    public var categoryIcon: String?
    public var categoryColor: String?

    public var accountName: String?
    public var accountType: String?
    public var accountIcon: String?
    public var accountColor: String?

    public init(
        localId: String = UUID().uuidString,
        serverId: Int? = nil,
        userId: Int,
        categoryId: Int,
        accountId: Int,
        type: String = "expense",
        amount: Double,
        transactionDescription: String,
        date: Int,
        hasTime: Bool = false,
        status: String = "active",
        isInstallment: Bool = false,
        installmentNumber: Int? = nil,
        totalInstallments: Int? = nil,
        installmentGroupId: String? = nil,
        createdAt: Int = Int(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int = Int(Date().timeIntervalSince1970 * 1000),
        syncStatus: String = "synced",
        categoryName: String? = nil,
        categoryIcon: String? = nil,
        categoryColor: String? = nil,
        accountName: String? = nil,
        accountType: String? = nil,
        accountIcon: String? = nil,
        accountColor: String? = nil
    ) {
        self.localId = localId
        self.serverId = serverId
        self.userId = userId
        self.categoryId = categoryId
        self.accountId = accountId
        self.type = type
        self.amount = amount
        self.transactionDescription = transactionDescription
        self.date = date
        self.hasTime = hasTime
        self.status = status
        self.isInstallment = isInstallment
        self.installmentNumber = installmentNumber
        self.totalInstallments = totalInstallments
        self.installmentGroupId = installmentGroupId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryColor = categoryColor
        self.accountName = accountName
        self.accountType = accountType
        self.accountIcon = accountIcon
        self.accountColor = accountColor
    }

    /// Converte a entidade local para o DTO TransactionModel utilizado na camada de apresentação.
    public func toModel() -> TransactionModel {
        var catDTO: CategoryRelationDTO? = nil
        if let categoryName {
            catDTO = CategoryRelationDTO(
                id: categoryId,
                name: categoryName,
                icon: categoryIcon ?? "tag.fill",
                color: categoryColor ?? "#FF9500"
            )
        }

        var accDTO: AccountRelationDTO? = nil
        if let accountName {
            accDTO = AccountRelationDTO(
                id: accountId,
                name: accountName,
                type: accountType ?? "credit_card",
                icon: accountIcon ?? "creditcard.fill",
                color: accountColor ?? "#007AFF"
            )
        }

        return TransactionModel(
            id: serverId ?? Int.random(in: 1_000_000...9_999_999),
            userId: userId,
            categoryId: categoryId,
            category: catDTO,
            accountId: accountId,
            account: accDTO,
            type: type,
            amount: Decimal(amount),
            description: transactionDescription,
            date: date,
            hasTime: hasTime,
            status: status,
            isInstallment: isInstallment,
            installmentNumber: installmentNumber,
            totalInstallments: totalInstallments,
            installmentGroupId: installmentGroupId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// Entidade local do SwiftData para cache de categorias.
@Model
public final class LocalCategory {
    @Attribute(.unique) public var id: Int
    public var userId: Int
    public var name: String
    public var icon: String
    public var color: String
    public var isDefault: Bool
    public var status: String
    public var createdAt: Int
    public var updatedAt: Int

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

    public func toModel() -> CategoryModel {
        CategoryModel(
            id: id,
            userId: userId,
            name: name,
            icon: icon,
            color: color,
            isDefault: isDefault,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// Entidade local do SwiftData para cache de contas e cartões.
@Model
public final class LocalAccount {
    @Attribute(.unique) public var id: Int
    public var userId: Int
    public var name: String
    public var type: String
    public var icon: String
    public var color: String
    public var allowsInstallments: Bool
    public var closingDay: Int?
    public var dueDay: Int?
    public var status: String
    public var createdAt: Int
    public var updatedAt: Int

    public init(
        id: Int,
        userId: Int,
        name: String,
        type: String,
        icon: String = "creditcard.fill",
        color: String = "#007AFF",
        allowsInstallments: Bool = false,
        closingDay: Int? = nil,
        dueDay: Int? = nil,
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

    public func toModel() -> AccountModel {
        AccountModel(
            id: id,
            userId: userId,
            name: name,
            type: type,
            icon: icon,
            color: color,
            allowsInstallments: allowsInstallments,
            closingDay: closingDay,
            dueDay: dueDay,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
