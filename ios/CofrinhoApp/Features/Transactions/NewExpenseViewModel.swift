import Foundation
import SwiftUI

@Observable
@MainActor
public final class NewExpenseViewModel {
    // MARK: - Campos do Formulário
    public var descriptionText: String = "" {
        didSet {
            filterSuggestions()
        }
    }
    public var notesText: String = ""
    public var rawAmount: Double = 0.0
    public var amountInputString: String = ""
    public var selectedDate: Date = Date()
    public var hasTime: Bool = false
    public var selectedCategory: CategoryModel?
    public var selectedAccount: AccountModel?
    public var selectedType: TransactionType = .expense {
        didSet {
            if selectedType == .income {
                isInstallmentsEnabled = false
            }
        }
    }
    public var isInstallmentsEnabled: Bool = false
    public var installmentsCount: Int = 2

    // MARK: - Dados Carregados
    public var categories: [CategoryModel] = []
    public var accounts: [AccountModel] = []
    public var allSuggestions: [SuggestionItemDTO] = []
    public var filteredSuggestions: [SuggestionItemDTO] = []

    // MARK: - Estados de Controle & Framework de Erros Cofrinho
    public var isLoading: Bool = false
    public var isSaving: Bool = false
    public var activeError: (any AppErrorProtocol)?
    public var successFeedback: String?
    public var showSuccessAlert: Bool = false

    // MARK: - Sheets Rápidas
    public var showCreateCategorySheet: Bool = false
    public var showCreateAccountSheet: Bool = false

    private let categoriesAPI = CategoriesAPIService.shared
    private let accountsAPI = AccountsAPIService.shared
    private let transactionsAPI = TransactionsAPIService.shared
    private let initialDate: Date?
    public private(set) var defaultType: TransactionType

    private static var lastRemoteSyncTimestamp: TimeInterval = 0
    private static var cachedRemoteSuggestions: [SuggestionItemDTO] = []

    public static func invalidateRemoteSyncCache() {
        lastRemoteSyncTimestamp = 0
        cachedRemoteSuggestions = []
    }

    public init(initialDate: Date? = nil, defaultType: TransactionType = .expense) {
        self.initialDate = initialDate
        self.defaultType = defaultType
        self.selectedDate = initialDate ?? Date()
        self.selectedType = defaultType
    }

    /// Atualiza em tempo real o tipo padrão de lançamento quando alterado nas preferências do usuário.
    public func applyDefaultType(_ newType: TransactionType) {
        self.defaultType = newType
        self.selectedType = newType
    }

    // MARK: - Formatação Monetária
    public func updateAmountFromDigits(_ input: String) {
        let cleanDigits = input.filter { $0.isNumber }
        if let cents = Double(cleanDigits) {
            rawAmount = cents / 100.0
        } else {
            rawAmount = 0.0
        }
        formatAmountString()
    }

    private func formatAmountString() {
        let formatted = rawAmount.brlCurrencyFormatted
        guard amountInputString != formatted else { return }
        amountInputString = formatted
    }

    // MARK: - Cálculo de Parcelamento e Datas de Fatura
    public var installmentSummaryText: String {
        guard rawAmount > 0, installmentsCount > 1 else { return "" }
        let perInstallment = rawAmount / Double(installmentsCount)
        return "\(installmentsCount)x de \(perInstallment.brlCurrencyFormatted)"
    }

    /// Retorna string com primeira e última fatura calculadas dinamicamente
    public var invoiceTimelineText: String {
        guard let account = selectedAccount, account.allowsInstallments else { return "" }
        let closingDay = account.closingDay ?? 20
        let dueDay = account.dueDay ?? 27

        let calendar = Calendar.current
        let purchaseDay = calendar.component(.day, from: selectedDate)
        let isAfterClosing = purchaseDay > closingDay
        let initialOffset = isAfterClosing ? 1 : 0

        // Primeira fatura
        guard let firstInvoiceDate = calendar.date(byAdding: .month, value: initialOffset, to: selectedDate) else {
            return ""
        }
        var firstComponents = calendar.dateComponents([.year, .month], from: firstInvoiceDate)
        firstComponents.day = min(dueDay, calendar.range(of: .day, in: .month, for: firstInvoiceDate)?.count ?? 30)
        let firstFinalDate = calendar.date(from: firstComponents) ?? firstInvoiceDate

        // Última fatura
        guard let lastInvoiceDate = calendar.date(byAdding: .month, value: initialOffset + installmentsCount - 1, to: selectedDate) else {
            return ""
        }
        var lastComponents = calendar.dateComponents([.year, .month], from: lastInvoiceDate)
        lastComponents.day = min(dueDay, calendar.range(of: .day, in: .month, for: lastInvoiceDate)?.count ?? 30)
        let lastFinalDate = calendar.date(from: lastComponents) ?? lastInvoiceDate

        return "Primeira fatura: \(firstFinalDate.brShortDateFormatted) • Última fatura: \(lastFinalDate.brShortDateFormatted)"
    }

    // MARK: - Carregamento Inicial
    public func loadInitialData(token: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // 1. Carregamento instantâneo do cache SwiftData / memória para 0 delay na UI
        let cachedCats = LocalDataManager.shared.fetchCachedCategories()
        if !cachedCats.isEmpty && self.categories.isEmpty {
            self.categories = cachedCats
            if selectedCategory == nil { selectedCategory = cachedCats.first }
        }

        let cachedAccs = LocalDataManager.shared.fetchCachedAccounts()
        if !cachedAccs.isEmpty && self.accounts.isEmpty {
            self.accounts = cachedAccs
            if selectedAccount == nil { selectedAccount = cachedAccs.first }
        }

        let warmupSuggestions = Self.cachedRemoteSuggestions.isEmpty
            ? deduplicateSuggestions(LocalDataManager.shared.fetchLocalPredictiveSuggestions())
            : Self.cachedRemoteSuggestions
        if !warmupSuggestions.isEmpty && self.allSuggestions.isEmpty {
            self.allSuggestions = warmupSuggestions
            filterSuggestions()
        }

        let now = Date().timeIntervalSinceReferenceDate
        let hasWarmCache = !self.categories.isEmpty && !self.accounts.isEmpty
        if hasWarmCache && (now - Self.lastRemoteSyncTimestamp) < 45 {
            return
        }

        // 2. Dispara sincronização em segundo plano de pendências offline
        Task {
            await LocalDataManager.shared.syncPendingTransactions(token: token)
        }

        // 3. Atualização paralela e resiliente de Categorias, Contas e Sugestões na VPS
        async let catsTask: ([CategoryModel]?, (any AppErrorProtocol)?) = {
            do {
                return (try await categoriesAPI.listCategories(token: token), nil)
            } catch {
                let normalized = CofrinhoErrorMapper.normalize(error)
                AppLogger.shared.warning("Falha ao carregar categorias remotas: \(normalized.errorDescription ?? error.localizedDescription)", category: .network)
                return (nil, normalized)
            }
        }()

        async let accsTask: ([AccountModel]?, (any AppErrorProtocol)?) = {
            do {
                return (try await accountsAPI.listAccounts(token: token), nil)
            } catch {
                let normalized = CofrinhoErrorMapper.normalize(error)
                AppLogger.shared.warning("Falha ao carregar contas remotas: \(normalized.errorDescription ?? error.localizedDescription)", category: .network)
                return (nil, normalized)
            }
        }()

        async let suggTask: [SuggestionItemDTO]? = {
            do {
                return try await transactionsAPI.getSuggestions(token: token)
            } catch {
                AppLogger.shared.warning("Falha ao buscar sugestões remotas (mantendo predição offline): \(error.localizedDescription)", category: .network)
                return nil
            }
        }()

        let ((loadedCats, catsErr), (loadedAccs, accsErr), loadedSugg) = await (catsTask, accsTask, suggTask)

        if let catsErr, (!CofrinhoErrorMapper.isConnectivityIssue(catsErr) || self.categories.isEmpty) {
            self.activeError = catsErr
        }

        if let accsErr, self.activeError == nil, (!CofrinhoErrorMapper.isConnectivityIssue(accsErr) || self.accounts.isEmpty) {
            self.activeError = accsErr
        }

        if let loadedCats {
            self.categories = loadedCats
            LocalDataManager.shared.cacheCategories(loadedCats)
            if selectedCategory == nil, let firstCat = loadedCats.first {
                selectedCategory = firstCat
            }
            AppLogger.shared.info("Categorias carregadas e sincronizadas (\(loadedCats.count)).", category: .network)
        }

        if let loadedAccs {
            self.accounts = loadedAccs
            LocalDataManager.shared.cacheAccounts(loadedAccs)
            if selectedAccount == nil, let firstAcc = loadedAccs.first {
                selectedAccount = firstAcc
            }
            AppLogger.shared.info("Contas carregadas e sincronizadas (\(loadedAccs.count)).", category: .network)
        }

        if let loadedSugg {
            let deduped = deduplicateSuggestions(loadedSugg)
            self.allSuggestions = deduped
            Self.cachedRemoteSuggestions = deduped
            filterSuggestions()
            AppLogger.shared.info("Sugestões preditivas carregadas (\(deduped.count)).", category: .network)
        }

        if loadedCats != nil && loadedAccs != nil {
            Self.lastRemoteSyncTimestamp = Date().timeIntervalSinceReferenceDate
        }
    }

    // MARK: - Autocomplete & Sugestões
    private func deduplicateSuggestions(_ items: [SuggestionItemDTO]) -> [SuggestionItemDTO] {
        var seen: Set<String> = []
        var result: [SuggestionItemDTO] = []
        for item in items {
            let cleanDesc = SuggestionItemDTO.sanitizeDescription(item.description)
            let key = cleanDesc.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(SuggestionItemDTO(
                description: cleanDesc,
                suggestedCategoryId: item.suggestedCategoryId,
                suggestedAccountId: item.suggestedAccountId,
                count: item.count
            ))
        }
        return result
    }

    private func filterSuggestions() {
        let query = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let newFiltered: [SuggestionItemDTO]
        if query.isEmpty {
            newFiltered = allSuggestions
        } else {
            newFiltered = allSuggestions.filter {
                $0.description.lowercased().contains(query)
            }
        }
        guard filteredSuggestions != newFiltered else { return }
        filteredSuggestions = newFiltered
    }

    public func applySuggestion(_ suggestion: SuggestionItemDTO) {
        descriptionText = suggestion.description

        if let catId = suggestion.suggestedCategoryId,
           let matchingCat = categories.first(where: { $0.id == catId }) {
            selectedCategory = matchingCat
        }

        if let accId = suggestion.suggestedAccountId,
           let matchingAcc = accounts.first(where: { $0.id == accId }) {
            selectedAccount = matchingAcc
        }
    }

    private func cachedUserProfile() -> UserProfileDTO? {
        guard let json = KeychainHelper.shared.read(key: "cofrinho_cached_user_json"),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(UserProfileDTO.self, from: data)
    }

    // MARK: - Submissão do Lançamento
    public func saveTransaction(token: String) async -> Bool {
        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDesc.isEmpty else {
            activeError = ValidationError.emptyTitle
            AppLogger.shared.warning("Validação falhou: Descrição vazia", category: .validation)
            return false
        }

        guard rawAmount > 0 else {
            activeError = ValidationError.invalidAmount
            AppLogger.shared.warning("Validação falhou: Valor zerado ou negativo", category: .validation)
            return false
        }

        guard let category = selectedCategory else {
            activeError = ValidationError.custom(message: "Por favor, selecione uma categoria para este lançamento.")
            AppLogger.shared.warning("Validação falhou: Nenhuma categoria selecionada", category: .validation)
            return false
        }

        guard let account = selectedAccount else {
            activeError = ValidationError.custom(message: "Por favor, selecione uma conta ou cartão de pagamento.")
            AppLogger.shared.warning("Validação falhou: Nenhuma conta selecionada", category: .validation)
            return false
        }

        isSaving = true
        defer { isSaving = false }

        let resolvedDate: Date = {
            if hasTime {
                return selectedDate
            }
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        }()

        let dateEpochMs = Int(resolvedDate.timeIntervalSince1970 * 1000)
        let trimmedNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let optionalNotes: String? = trimmedNotes.isEmpty ? nil : trimmedNotes
        let canInstallments = selectedType == .expense && isInstallmentsEnabled && account.allowsInstallments

        do {
            let created = try await transactionsAPI.createTransaction(
                token: token,
                description: trimmedDesc,
                notes: optionalNotes,
                amount: rawAmount,
                date: dateEpochMs,
                hasTime: hasTime,
                categoryId: category.id,
                accountId: account.id,
                type: selectedType.rawValue,
                installmentsEnabled: canInstallments,
                installmentsCount: installmentsCount
            )

            // Atualiza cache local instantaneamente e invalida cache remoto de sugestões/auxiliares
            LocalDataManager.shared.cacheTransactions([created])
            Self.invalidateRemoteSyncCache()

            if canInstallments {
                successFeedback = "Gasto parcelado em \(installmentsCount)x cadastrado com sucesso!"
            } else if selectedType == .income {
                successFeedback = "Receita cadastrada com sucesso!"
            } else {
                successFeedback = "Gasto cadastrado com sucesso!"
            }
            showSuccessAlert = true
            resetForm()
            AppLogger.shared.info("Lançamento registrado com sucesso: \(trimmedDesc) (\(selectedType.rawValue))", category: .business)
            return true
        } catch let netErr as NetworkError where isConnectionError(netErr) {
            // MARK: - Modo Offline Resiliente (SwiftData)
            let cachedUser = cachedUserProfile()
            LocalDataManager.shared.saveOfflineTransaction(
                userId: category.userId,
                description: trimmedDesc,
                notes: optionalNotes,
                amount: rawAmount,
                date: dateEpochMs,
                hasTime: hasTime,
                category: category,
                account: account,
                type: selectedType.rawValue,
                createdByUserId: cachedUser?.id ?? category.userId,
                createdByUsername: cachedUser?.username,
                isInstallment: canInstallments,
                installmentsCount: installmentsCount
            )
            Self.invalidateRemoteSyncCache()

            successFeedback = "Lançamento salvo no modo offline! Será sincronizado automaticamente assim que você se reconectar."
            showSuccessAlert = true
            resetForm()
            AppLogger.shared.warning("Lançamento salvo localmente em modo offline devido a falha de conexão.", category: .database)
            return true
        } catch let err as any AppErrorProtocol {
            self.activeError = err
            AppLogger.shared.error("Falha ao registrar lançamento: \(err.errorDescription ?? err.localizedDescription)", category: .network)
            return false
        } catch {
            let unk = NetworkError.unknown(reason: error.localizedDescription)
            self.activeError = unk
            AppLogger.shared.error("Erro inesperado ao registrar lançamento: \(error.localizedDescription)", category: .network)
            return false
        }
    }

    private func isConnectionError(_ error: NetworkError) -> Bool {
        CofrinhoErrorMapper.isConnectivityIssue(error)
    }

    private func resetForm() {
        descriptionText = ""
        notesText = ""
        rawAmount = 0.0
        amountInputString = ""
        selectedDate = initialDate ?? Date()
        hasTime = false
        selectedType = defaultType
        isInstallmentsEnabled = false
        installmentsCount = 2
    }
}
