import Foundation
import SwiftData

/// Gerenciador central de persistência e sincronização offline com SwiftData para o Cofrinho.
/// Permite funcionamento instantâneo da interface (0ms), cache resiliente e sincronização
/// em segundo plano de gastos registrados offline.
@MainActor
public final class LocalDataManager {
    public static let shared = LocalDataManager()

    public let container: ModelContainer
    public var context: ModelContext {
        container.mainContext
    }

    private init() {
        do {
            let schema = Schema([
                LocalTransaction.self,
                LocalCategory.self,
                LocalAccount.self
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.container = try ModelContainer(for: schema, configurations: [config])
            AppLogger.shared.info("SwiftData ModelContainer inicializado com sucesso.", category: .database)
        } catch {
            AppLogger.shared.critical("Falha ao inicializar SwiftData ModelContainer: \(error.localizedDescription)", category: .database)
            fatalError("Não foi possível inicializar o SwiftData: \(error)")
        }
    }

    // MARK: - Gestão de Transações no Cache

    /// Salva ou atualiza uma lista de transações retornadas pelo servidor no SwiftData.
    public func cacheTransactions(_ transactions: [TransactionModel]) {
        for tx in transactions {
            let serverId = tx.id
            var descriptor = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate { $0.serverId == serverId }
            )
            descriptor.fetchLimit = 1

            if let existing = try? context.fetch(descriptor).first {
                existing.amount = NSDecimalNumber(decimal: tx.amount).doubleValue
                existing.transactionDescription = tx.description
                existing.date = tx.date
                existing.hasTime = tx.hasTime
                existing.status = tx.status
                existing.categoryId = tx.categoryId
                existing.categoryName = tx.category?.name
                existing.categoryIcon = tx.category?.icon
                existing.categoryColor = tx.category?.color
                existing.accountId = tx.accountId
                existing.accountName = tx.account?.name
                existing.accountType = tx.account?.type
                existing.accountIcon = tx.account?.icon
                existing.accountColor = tx.account?.color
                existing.isInstallment = tx.isInstallment
                existing.installmentNumber = tx.installmentNumber
                existing.totalInstallments = tx.totalInstallments
                existing.installmentGroupId = tx.installmentGroupId
                existing.updatedAt = tx.updatedAt
                existing.syncStatus = "synced"
            } else {
                let local = LocalTransaction(
                    serverId: tx.id,
                    userId: tx.userId,
                    categoryId: tx.categoryId,
                    accountId: tx.accountId,
                    type: tx.type,
                    amount: NSDecimalNumber(decimal: tx.amount).doubleValue,
                    transactionDescription: tx.description,
                    date: tx.date,
                    hasTime: tx.hasTime,
                    status: tx.status,
                    isInstallment: tx.isInstallment,
                    installmentNumber: tx.installmentNumber,
                    totalInstallments: tx.totalInstallments,
                    installmentGroupId: tx.installmentGroupId,
                    createdAt: tx.createdAt,
                    updatedAt: tx.updatedAt,
                    syncStatus: "synced",
                    categoryName: tx.category?.name,
                    categoryIcon: tx.category?.icon,
                    categoryColor: tx.category?.color,
                    accountName: tx.account?.name,
                    accountType: tx.account?.type,
                    accountIcon: tx.account?.icon,
                    accountColor: tx.account?.color
                )
                context.insert(local)
            }
        }

        try? context.save()
    }

    /// Busca transações armazenadas localmente para um mês e ano específicos com filtros opcionais.
    public func fetchCachedTransactions(
        month: Int,
        year: Int,
        categoryId: Int? = nil,
        accountId: Int? = nil,
        status: String = "active"
    ) -> [TransactionModel] {
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = month
        startComponents.day = 1
        startComponents.hour = 0
        startComponents.minute = 0
        startComponents.second = 0
        let startDate = Calendar.current.date(from: startComponents) ?? Date()
        let startEpoch = Int(startDate.timeIntervalSince1970 * 1000)

        var endComponents = DateComponents()
        endComponents.year = month == 12 ? year + 1 : year
        endComponents.month = month == 12 ? 1 : month + 1
        endComponents.day = 1
        endComponents.hour = 0
        endComponents.minute = 0
        endComponents.second = 0
        let endDate = Calendar.current.date(from: endComponents) ?? Date()
        let endEpoch = Int(endDate.timeIntervalSince1970 * 1000)

        let descriptor = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate { $0.date >= startEpoch && $0.date < endEpoch && $0.status != "deleted" },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let entities = (try? context.fetch(descriptor)) ?? []
        return entities
            .filter { item in
                if status == "active" && item.status != "active" { return false }
                if status == "hidden" && item.status != "hidden" { return false }
                if let categoryId, item.categoryId != categoryId { return false }
                if let accountId, item.accountId != accountId { return false }
                return true
            }
            .map { $0.toModel() }
    }

    /// Salva um novo gasto localmente quando o dispositivo estiver offline.
    @discardableResult
    public func saveOfflineTransaction(
        userId: Int,
        description: String,
        amount: Double,
        date: Int,
        hasTime: Bool,
        category: CategoryModel,
        account: AccountModel,
        isInstallment: Bool = false,
        installmentsCount: Int = 1
    ) -> TransactionModel {
        let local = LocalTransaction(
            userId: userId,
            categoryId: category.id,
            accountId: account.id,
            type: "expense",
            amount: amount,
            transactionDescription: description,
            date: date,
            hasTime: hasTime,
            status: "active",
            isInstallment: isInstallment,
            totalInstallments: isInstallment ? installmentsCount : nil,
            syncStatus: "pending_create",
            categoryName: category.name,
            categoryIcon: category.icon,
            categoryColor: category.color,
            accountName: account.name,
            accountType: account.type,
            accountIcon: account.icon,
            accountColor: account.color
        )

        context.insert(local)
        try? context.save()
        AppLogger.shared.info("Gasto registrado offline com sucesso (localId: \(local.localId)).", category: .database)
        return local.toModel()
    }

    /// Sincroniza todas as transações pendentes criadas offline com a VPS.
    public func syncPendingTransactions(token: String) async {
        let descriptor = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate { $0.syncStatus == "pending_create" }
        )

        guard let pendings = try? context.fetch(descriptor), !pendings.isEmpty else {
            return
        }

        AppLogger.shared.info("Iniciando sincronização de \(pendings.count) transações pendentes com a VPS...", category: .network)

        for item in pendings {
            do {
                let created = try await TransactionsAPIService.shared.createTransaction(
                    token: token,
                    description: item.transactionDescription,
                    amount: item.amount,
                    date: item.date,
                    hasTime: item.hasTime,
                    categoryId: item.categoryId,
                    accountId: item.accountId,
                    type: item.type,
                    installmentsEnabled: item.isInstallment,
                    installmentsCount: item.totalInstallments ?? 2
                )

                item.serverId = created.id
                item.syncStatus = "synced"
                item.updatedAt = created.updatedAt
                try? context.save()
                AppLogger.shared.info("Transação offline \(item.localId) sincronizada com sucesso (serverId: \(created.id)).", category: .network)
            } catch {
                AppLogger.shared.warning("Falha ao sincronizar item offline \(item.localId): \(error.localizedDescription)", category: .network)
                break // Se a conexão falhou, interrompe e tenta na próxima janela
            }
        }
    }

    // MARK: - Gestão de Categorias e Contas no Cache

    public func cacheCategories(_ categories: [CategoryModel]) {
        for cat in categories {
            let catId = cat.id
            var descriptor = FetchDescriptor<LocalCategory>(
                predicate: #Predicate { $0.id == catId }
            )
            descriptor.fetchLimit = 1

            if let existing = try? context.fetch(descriptor).first {
                existing.name = cat.name
                existing.icon = cat.icon
                existing.color = cat.color
                existing.isDefault = cat.isDefault
                existing.status = cat.status
                existing.updatedAt = cat.updatedAt
            } else {
                let local = LocalCategory(
                    id: cat.id,
                    userId: cat.userId,
                    name: cat.name,
                    icon: cat.icon,
                    color: cat.color,
                    isDefault: cat.isDefault,
                    status: cat.status,
                    createdAt: cat.createdAt,
                    updatedAt: cat.updatedAt
                )
                context.insert(local)
            }
        }
        try? context.save()
    }

    public func fetchCachedCategories() -> [CategoryModel] {
        let descriptor = FetchDescriptor<LocalCategory>(
            predicate: #Predicate { $0.status == "active" },
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        return entities.map { $0.toModel() }
    }

    public func cacheAccounts(_ accounts: [AccountModel]) {
        for acc in accounts {
            let accId = acc.id
            var descriptor = FetchDescriptor<LocalAccount>(
                predicate: #Predicate { $0.id == accId }
            )
            descriptor.fetchLimit = 1

            if let existing = try? context.fetch(descriptor).first {
                existing.name = acc.name
                existing.type = acc.type
                existing.icon = acc.icon
                existing.color = acc.color
                existing.allowsInstallments = acc.allowsInstallments
                existing.closingDay = acc.closingDay
                existing.dueDay = acc.dueDay
                existing.status = acc.status
                existing.updatedAt = acc.updatedAt
            } else {
                let local = LocalAccount(
                    id: acc.id,
                    userId: acc.userId,
                    name: acc.name,
                    type: acc.type,
                    icon: acc.icon,
                    color: acc.color,
                    allowsInstallments: acc.allowsInstallments,
                    closingDay: acc.closingDay,
                    dueDay: acc.dueDay,
                    status: acc.status,
                    createdAt: acc.createdAt,
                    updatedAt: acc.updatedAt
                )
                context.insert(local)
            }
        }
        try? context.save()
    }

    public func fetchCachedAccounts() -> [AccountModel] {
        let descriptor = FetchDescriptor<LocalAccount>(
            predicate: #Predicate { $0.status == "active" },
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        return entities.map { $0.toModel() }
    }
}

