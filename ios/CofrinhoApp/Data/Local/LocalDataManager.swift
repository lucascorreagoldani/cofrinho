import Foundation
import SwiftData

/// Gerenciador central de persistência e sincronização offline com SwiftData para o Cofrinho.
/// Permite funcionamento instantâneo da interface (0ms), cache resiliente e sincronização
/// em segundo plano de criações, alterações de visibilidade e exclusões realizadas offline.
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
    /// Preserva mutações locais ainda não sincronizadas (pending_update / pending_delete).
    public func cacheTransactions(_ transactions: [TransactionModel]) {
        let syncedRaw = SyncStatus.synced.rawValue

        for tx in transactions {
            let serverId = tx.id
            var descriptor = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate { $0.serverId == serverId }
            )
            descriptor.fetchLimit = 1

            if let existing = try? context.fetch(descriptor).first {
                guard existing.syncStatus == syncedRaw else {
                    continue
                }
                existing.amount = NSDecimalNumber(decimal: tx.amount).doubleValue
                existing.transactionDescription = tx.description
                existing.notes = tx.notes
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
                existing.isModified = tx.isModified
                existing.modifiedAt = tx.modifiedAt
                existing.createdByUserId = tx.createdByUserId
                existing.createdByUsername = tx.createdBy?.username
                existing.updatedByUserId = tx.updatedByUserId
                existing.updatedByUsername = tx.updatedBy?.username
                existing.updatedByEmail = tx.updatedBy?.email
                existing.updatedAt = tx.updatedAt
                existing.syncStatus = syncedRaw
            } else {
                let local = LocalTransaction(
                    serverId: tx.id,
                    userId: tx.userId,
                    categoryId: tx.categoryId,
                    accountId: tx.accountId,
                    type: tx.type,
                    amount: NSDecimalNumber(decimal: tx.amount).doubleValue,
                    transactionDescription: tx.description,
                    notes: tx.notes,
                    date: tx.date,
                    hasTime: tx.hasTime,
                    status: tx.status,
                    isInstallment: tx.isInstallment,
                    installmentNumber: tx.installmentNumber,
                    totalInstallments: tx.totalInstallments,
                    installmentGroupId: tx.installmentGroupId,
                    isModified: tx.isModified,
                    modifiedAt: tx.modifiedAt,
                    createdByUserId: tx.createdByUserId,
                    createdByUsername: tx.createdBy?.username,
                    updatedByUserId: tx.updatedByUserId,
                    updatedByUsername: tx.updatedBy?.username,
                    updatedByEmail: tx.updatedBy?.email,
                    createdAt: tx.createdAt,
                    updatedAt: tx.updatedAt,
                    syncStatus: syncedRaw,
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
        status: TransactionFilterStatus = .active
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

        let deletedRaw = RecordStatus.deleted.rawValue
        let descriptor = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate { $0.date >= startEpoch && $0.date < endEpoch && $0.status != deletedRaw },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let entities = (try? context.fetch(descriptor)) ?? []
        return entities
            .filter { item in
                let itemStatus = RecordStatus(rawValue: item.status) ?? .active
                switch status {
                case .active:
                    if itemStatus != .active { return false }
                case .hidden:
                    if itemStatus != .hidden { return false }
                case .all:
                    if itemStatus == .deleted { return false }
                }
                if let categoryId, item.categoryId != categoryId { return false }
                if let accountId, item.accountId != accountId { return false }
                return true
            }
            .map { $0.toModel() }
    }

    /// Busca todas as transações ativas cacheadas no SwiftData ordenadas por data decrescente para o Hub Início.
    public func fetchAllActiveCachedTransactions(userId: Int? = nil) -> [TransactionModel] {
        let activeRaw = RecordStatus.active.rawValue
        let descriptor = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate { $0.status == activeRaw },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let entities = (try? context.fetch(descriptor)) ?? []
        return entities
            .filter { item in
                if let userId, userId > 0, item.userId != userId {
                    return false
                }
                return true
            }
            .map { $0.toModel() }
    }

    /// Salva um novo lançamento localmente quando o dispositivo estiver offline.
    @discardableResult
    public func saveOfflineTransaction(
        userId: Int,
        description: String,
        notes: String? = nil,
        amount: Double,
        date: Int,
        hasTime: Bool,
        category: CategoryModel,
        account: AccountModel,
        type: String = TransactionType.expense.rawValue,
        createdByUserId: Int? = nil,
        createdByUsername: String? = nil,
        isInstallment: Bool = false,
        installmentsCount: Int = 1
    ) -> TransactionModel {
        let local = LocalTransaction(
            userId: userId,
            categoryId: category.id,
            accountId: account.id,
            type: type,
            amount: amount,
            transactionDescription: description,
            notes: notes,
            date: date,
            hasTime: hasTime,
            status: RecordStatus.active.rawValue,
            isInstallment: isInstallment,
            totalInstallments: isInstallment ? installmentsCount : nil,
            createdByUserId: createdByUserId ?? userId,
            createdByUsername: createdByUsername,
            syncStatus: SyncStatus.pendingCreate.rawValue,
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
        AppLogger.shared.info("Lançamento registrado offline com sucesso (localId: \(local.localId)).", category: .database)
        return local.toModel()
    }

    /// Marca uma transação para exclusão offline (ou remove imediatamente se ainda não foi sincronizada).
    public func markOfflineDelete(id: Int, cascade: DeleteCascadeMode = .single) {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        guard let target = findLocalTransaction(byDisplayId: id) else { return }

        if cascade == .allFuture,
           let groupId = target.installmentGroupId,
           let currentNum = target.installmentNumber {
            let groupDescriptor = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate { $0.installmentGroupId == groupId }
            )
            let matches = (try? context.fetch(groupDescriptor)) ?? []
            for item in matches where (item.installmentNumber ?? 0) >= currentNum {
                applyOfflineDelete(to: item, nowMs: nowMs)
            }
        } else {
            applyOfflineDelete(to: target, nowMs: nowMs)
        }

        try? context.save()
    }

    /// Alterna a visibilidade (active <-> hidden) localmente no SwiftData e agenda sincronização.
    public func markOfflineToggleVisibility(id: Int) {
        guard let item = findLocalTransaction(byDisplayId: id) else { return }

        let currentStatus = RecordStatus(rawValue: item.status) ?? .active
        let newStatus: RecordStatus = (currentStatus == .hidden) ? .active : .hidden
        item.status = newStatus.rawValue
        item.updatedAt = Int(Date().timeIntervalSince1970 * 1000)

        if item.syncStatus == SyncStatus.synced.rawValue {
            item.syncStatus = SyncStatus.pendingUpdate.rawValue
        }

        try? context.save()
        AppLogger.shared.info("Visibilidade alterada offline para \(newStatus.rawValue) (id: \(id)).", category: .database)
    }

    /// Atualiza as observações de um lançamento localmente no SwiftData e agenda sincronização.
    public func markOfflineUpdateNotes(id: Int, notes: String?) {
        guard let item = findLocalTransaction(byDisplayId: id) else { return }
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = (trimmed?.isEmpty ?? true) ? nil : trimmed
        item.isModified = true
        item.modifiedAt = nowMs
        item.updatedAt = nowMs

        if item.syncStatus == SyncStatus.synced.rawValue {
            item.syncStatus = SyncStatus.pendingUpdate.rawValue
        }

        try? context.save()
        AppLogger.shared.info("Observações atualizadas offline para transação (id: \(id)).", category: .database)
    }

    /// Atualiza todos os campos editáveis de um lançamento localmente no SwiftData e agenda sincronização com a VPS.
    public func markOfflineUpdateTransaction(
        id: Int,
        description: String,
        notes: String?,
        amount: Double,
        date: Int,
        hasTime: Bool,
        category: CategoryModel,
        account: AccountModel,
        type: String,
        status: String,
        modifiedByUserId: Int?,
        modifiedByUsername: String?,
        modifiedByEmail: String?
    ) {
        guard let item = findLocalTransaction(byDisplayId: id) else { return }
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)

        item.transactionDescription = description
        item.notes = (trimmedNotes?.isEmpty ?? true) ? nil : trimmedNotes
        item.amount = amount
        item.date = date
        item.hasTime = hasTime
        item.categoryId = category.id
        item.categoryName = category.name
        item.categoryIcon = category.icon
        item.categoryColor = category.color
        item.accountId = account.id
        item.accountName = account.name
        item.accountType = account.type
        item.accountIcon = account.icon
        item.accountColor = account.color
        item.type = type
        item.status = status
        item.isModified = true
        item.modifiedAt = nowMs
        item.updatedAt = nowMs
        if let modifiedByUserId {
            item.updatedByUserId = modifiedByUserId
        }
        if let modifiedByUsername {
            item.updatedByUsername = modifiedByUsername
        }
        if let modifiedByEmail {
            item.updatedByEmail = modifiedByEmail
        }

        if item.syncStatus == SyncStatus.synced.rawValue {
            item.syncStatus = SyncStatus.pendingUpdate.rawValue
        }

        try? context.save()
        AppLogger.shared.info("Lançamento atualizado offline para sincronização (id: \(id)).", category: .database)
    }

    /// Busca todas as parcelas armazenadas no SwiftData para um mesmo installment_group_id.
    public func fetchCachedInstallmentGroup(groupId: String) -> [TransactionModel] {
        let deletedRaw = RecordStatus.deleted.rawValue
        let descriptor = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate { $0.installmentGroupId == groupId && $0.status != deletedRaw },
            sortBy: [
                SortDescriptor(\.installmentNumber, order: .forward),
                SortDescriptor(\.date, order: .forward)
            ]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        return entities.map { $0.toModel() }
    }

    /// Remove ou marca como deletado no cache local após confirmação de exclusão bem-sucedida na VPS.
    public func removeSyncedTransaction(id: Int, cascade: DeleteCascadeMode = .single) {
        guard let target = findLocalTransaction(byDisplayId: id) else { return }

        if cascade == .allFuture,
           let groupId = target.installmentGroupId,
           let currentNum = target.installmentNumber {
            let groupDescriptor = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate { $0.installmentGroupId == groupId }
            )
            let matches = (try? context.fetch(groupDescriptor)) ?? []
            for item in matches where (item.installmentNumber ?? 0) >= currentNum {
                context.delete(item)
            }
        } else {
            context.delete(target)
        }

        try? context.save()
    }

    /// Sincroniza todas as mutações pendentes offline (`pending_create`, `pending_update`, `pending_delete`) com a VPS.
    public func syncPendingTransactions(token: String) async {
        let syncedRaw = SyncStatus.synced.rawValue
        let descriptor = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate { $0.syncStatus != syncedRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        guard let pendings = try? context.fetch(descriptor), !pendings.isEmpty else {
            return
        }

        AppLogger.shared.info("Iniciando sincronização de \(pendings.count) operações offline pendentes com a VPS...", category: .network)

        for item in pendings {
            let currentSync = SyncStatus(rawValue: item.syncStatus) ?? .synced
            do {
                switch currentSync {
                case .pendingCreate:
                    let created = try await TransactionsAPIService.shared.createTransaction(
                        token: token,
                        description: item.transactionDescription,
                        notes: item.notes,
                        amount: item.amount,
                        date: item.date,
                        hasTime: item.hasTime,
                        categoryId: item.categoryId,
                        accountId: item.accountId,
                        type: item.type,
                        installmentsEnabled: item.isInstallment,
                        installmentsCount: item.totalInstallments ?? 2
                    )

                    if item.status == RecordStatus.hidden.rawValue {
                        _ = try await TransactionsAPIService.shared.updateTransaction(
                            token: token,
                            id: created.id,
                            status: RecordStatus.hidden.rawValue
                        )
                    }

                    item.serverId = created.id
                    item.createdByUserId = created.createdByUserId
                    item.createdByUsername = created.createdBy?.username
                    item.syncStatus = SyncStatus.synced.rawValue
                    item.updatedAt = created.updatedAt
                    try? context.save()
                    AppLogger.shared.info("Criação offline \(item.localId) sincronizada (serverId: \(created.id)).", category: .network)

                case .pendingUpdate:
                    if let serverId = item.serverId {
                        let updated = try await TransactionsAPIService.shared.updateTransaction(
                            token: token,
                            id: serverId,
                            description: item.transactionDescription,
                            notes: item.notes ?? "",
                            amount: item.amount,
                            date: item.date,
                            hasTime: item.hasTime,
                            categoryId: item.categoryId,
                            accountId: item.accountId,
                            type: item.type,
                            status: item.status
                        )
                        item.isModified = updated.isModified
                        item.modifiedAt = updated.modifiedAt
                        item.createdByUserId = updated.createdByUserId
                        item.createdByUsername = updated.createdBy?.username
                        item.updatedByUserId = updated.updatedByUserId
                        item.updatedByUsername = updated.updatedBy?.username
                        item.updatedByEmail = updated.updatedBy?.email
                        item.syncStatus = SyncStatus.synced.rawValue
                        item.updatedAt = updated.updatedAt
                        try? context.save()
                        AppLogger.shared.info("Atualização offline \(serverId) sincronizada (status: \(item.status)).", category: .network)
                    }

                case .pendingDelete:
                    if let serverId = item.serverId {
                        try await TransactionsAPIService.shared.deleteTransaction(
                            token: token,
                            id: serverId,
                            cascade: .single
                        )
                    }
                    context.delete(item)
                    try? context.save()
                    AppLogger.shared.info("Exclusão offline \(item.localId) sincronizada com a VPS.", category: .network)

                case .synced:
                    break
                }
            } catch {
                AppLogger.shared.warning("Falha ao sincronizar item offline \(item.localId): \(error.localizedDescription)", category: .network)
                break
            }
        }
    }

    // MARK: - Helpers Privados de Transações Locais

    private func findLocalTransaction(byDisplayId id: Int) -> LocalTransaction? {
        if id > 0 {
            var descriptor = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate { $0.serverId == id }
            )
            descriptor.fetchLimit = 1
            return try? context.fetch(descriptor).first
        } else {
            let descriptor = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate { $0.serverId == nil }
            )
            let unsynced = (try? context.fetch(descriptor)) ?? []
            return unsynced.first(where: { $0.stableDisplayId == id })
        }
    }

    private func applyOfflineDelete(to item: LocalTransaction, nowMs: Int) {
        if item.syncStatus == SyncStatus.pendingCreate.rawValue && item.serverId == nil {
            context.delete(item)
            AppLogger.shared.info("Transação offline não sincronizada removida localmente (\(item.localId)).", category: .database)
        } else {
            item.status = RecordStatus.deleted.rawValue
            item.syncStatus = SyncStatus.pendingDelete.rawValue
            item.updatedAt = nowMs
            AppLogger.shared.info("Exclusão offline marcada para sincronização (serverId: \(item.serverId ?? 0)).", category: .database)
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
        let activeRaw = RecordStatus.active.rawValue
        let descriptor = FetchDescriptor<LocalCategory>(
            predicate: #Predicate { $0.status == activeRaw },
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
        let activeRaw = RecordStatus.active.rawValue
        let descriptor = FetchDescriptor<LocalAccount>(
            predicate: #Predicate { $0.status == activeRaw },
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        return entities.map { $0.toModel() }
    }

    // MARK: - Sugestões Preditivas Locais (Fallback Offline)

    /// Calcula sugestões preditivas locais no SwiftData analisando horário, dia da semana,
    /// recência e demanda, removendo sufixos de parcelamento/quantidade.
    public func fetchLocalPredictiveSuggestions(limit: Int = 8) -> [SuggestionItemDTO] {
        let deletedRaw = RecordStatus.deleted.rawValue
        var descriptor = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate {
                $0.status != deletedRaw && (!$0.isInstallment || $0.installmentNumber == 1)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 250

        let items = (try? context.fetch(descriptor)) ?? []
        guard !items.isEmpty else { return [] }

        let now = Date()
        let nowMs = Int(now.timeIntervalSince1970 * 1000)
        let calendar = Calendar.current
        let nowHour = Double(calendar.component(.hour, from: now)) + Double(calendar.component(.minute, from: now)) / 60.0
        let nowWeekday = calendar.component(.weekday, from: now)
        let nowIsWeekend = (nowWeekday == 1 || nowWeekday == 7)

        struct GroupStats {
            var displayName: String
            var count: Int = 0
            var lastCreatedAt: Int
            var maxTimeBonus: Double = 0
            var timeAffinitySum: Double = 0
            var maxDayBonus: Double = 0
            var dayAffinitySum: Double = 0
            var categoryCounts: [Int: Int] = [:]
            var accountCounts: [Int: Int] = [:]
        }

        var groups: [String: GroupStats] = [:]

        for item in items {
            let cleanDesc = SuggestionItemDTO.sanitizeDescription(item.transactionDescription)
            let key = cleanDesc.lowercased()
            guard !key.isEmpty else { continue }

            let txTs = item.createdAt > 0 ? item.createdAt : item.date
            let txDate = Date(timeIntervalSince1970: TimeInterval(txTs) / 1000.0)
            let txHour = Double(calendar.component(.hour, from: txDate)) + Double(calendar.component(.minute, from: txDate)) / 60.0
            let txWeekday = calendar.component(.weekday, from: txDate)
            let txIsWeekend = (txWeekday == 1 || txWeekday == 7)

            let rawHourDiff = abs(nowHour - txHour)
            let circularDiff = min(rawHourDiff, 24.0 - rawHourDiff)

            let timeBonus: Double
            if circularDiff <= 1.0 {
                timeBonus = 35.0
            } else if circularDiff <= 3.0 {
                timeBonus = 20.0
            } else if circularDiff <= 5.0 {
                timeBonus = 8.0
            } else {
                timeBonus = 0.0
            }

            let dayBonus: Double
            if txWeekday == nowWeekday {
                dayBonus = 20.0
            } else if txIsWeekend == nowIsWeekend {
                dayBonus = 8.0
            } else {
                dayBonus = 0.0
            }

            var group = groups[key] ?? GroupStats(displayName: cleanDesc, lastCreatedAt: txTs)
            group.count += 1
            if txTs > group.lastCreatedAt {
                group.lastCreatedAt = txTs
                group.displayName = cleanDesc
            }
            group.maxTimeBonus = max(group.maxTimeBonus, timeBonus)
            group.timeAffinitySum += timeBonus
            group.maxDayBonus = max(group.maxDayBonus, dayBonus)
            group.dayAffinitySum += dayBonus
            group.categoryCounts[item.categoryId, default: 0] += 1
            group.accountCounts[item.accountId, default: 0] += 1
            groups[key] = group
        }

        let scored = groups.values.map { group -> (dto: SuggestionItemDTO, score: Double, lastTs: Int) in
            let avgTime = group.timeAffinitySum / Double(group.count)
            let avgDay = group.dayAffinitySum / Double(group.count)
            let timeScore = group.maxTimeBonus * 0.65 + avgTime * 0.35
            let dayScore = group.maxDayBonus * 0.70 + avgDay * 0.30
            let daysSinceLast = max(0.0, Double(nowMs - group.lastCreatedAt) / (1000.0 * 60.0 * 60.0 * 24.0))
            let recencyScore = 35.0 * exp(-daysSinceLast / 14.0)
            let demandScore = min(30.0, log2(Double(group.count) + 1.0) * 12.0)

            let topCat = group.categoryCounts.max(by: { $0.value < $1.value })?.key
            let topAcc = group.accountCounts.max(by: { $0.value < $1.value })?.key

            let dto = SuggestionItemDTO(
                description: group.displayName,
                suggestedCategoryId: topCat,
                suggestedAccountId: topAcc,
                count: group.count
            )
            return (dto, timeScore + dayScore + recencyScore + demandScore, group.lastCreatedAt)
        }
        .sorted {
            if abs($0.score - $1.score) > 0.001 {
                return $0.score > $1.score
            }
            return $0.lastTs > $1.lastTs
        }

        return Array(scored.prefix(limit).map { $0.dto })
    }
}
