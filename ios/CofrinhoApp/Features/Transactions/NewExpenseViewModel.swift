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
    public var rawAmount: Double = 0.0
    public var amountInputString: String = ""
    public var selectedDate: Date = Date()
    public var hasTime: Bool = false
    public var selectedCategory: CategoryModel?
    public var selectedAccount: AccountModel?
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

    public init() {}

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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.locale = Locale(identifier: "pt_BR")
        amountInputString = formatter.string(from: NSNumber(value: rawAmount)) ?? "R$ 0,00"
    }

    // MARK: - Cálculo de Parcelamento e Datas de Fatura
    public var installmentSummaryText: String {
        guard rawAmount > 0, installmentsCount > 1 else { return "" }
        let perInstallment = rawAmount / Double(installmentsCount)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.locale = Locale(identifier: "pt_BR")
        let formattedVal = formatter.string(from: NSNumber(value: perInstallment)) ?? "R$ 0,00"
        return "\(installmentsCount)x de \(formattedVal)"
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

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        let firstStr = dateFormatter.string(from: firstFinalDate)
        let lastStr = dateFormatter.string(from: lastFinalDate)

        return "Primeira fatura: \(firstStr) • Última fatura: \(lastStr)"
    }

    // MARK: - Carregamento Inicial
    public func loadInitialData(token: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // Carrega categorias de forma resiliente
        do {
            let loadedCats = try await categoriesAPI.listCategories(token: token)
            self.categories = loadedCats
            if selectedCategory == nil, let firstCat = loadedCats.first {
                selectedCategory = firstCat
            }
            AppLogger.shared.info("Categorias carregadas com sucesso (\(loadedCats.count)).", category: .network)
        } catch {
            AppLogger.shared.warning("Falha ao carregar categorias no startup: \(error.localizedDescription)", category: .network)
        }

        // Carrega contas de forma resiliente
        do {
            let loadedAccs = try await accountsAPI.listAccounts(token: token)
            self.accounts = loadedAccs
            if selectedAccount == nil, let firstAcc = loadedAccs.first {
                selectedAccount = firstAcc
            }
            AppLogger.shared.info("Contas carregadas com sucesso (\(loadedAccs.count)).", category: .network)
        } catch {
            AppLogger.shared.warning("Falha ao carregar contas no startup: \(error.localizedDescription)", category: .network)
        }

        // Carrega sugestões de gastos frequentes
        do {
            let loadedSugg = try await transactionsAPI.getSuggestions(token: token)
            self.allSuggestions = loadedSugg
            self.filteredSuggestions = loadedSugg
            AppLogger.shared.info("Sugestões de histórico carregadas (\(loadedSugg.count)).", category: .network)
        } catch {
            AppLogger.shared.warning("Falha ao buscar sugestões no startup: \(error.localizedDescription)", category: .network)
        }
    }

    // MARK: - Autocomplete & Sugestões
    private func filterSuggestions() {
        let query = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredSuggestions = allSuggestions
        } else {
            filteredSuggestions = allSuggestions.filter {
                $0.description.lowercased().contains(query)
            }
        }
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

    // MARK: - Submissão do Gasto
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
            activeError = ValidationError.custom(message: "Por favor, selecione uma categoria para este gasto.")
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

        let dateEpochMs = Int(selectedDate.timeIntervalSince1970 * 1000)

        do {
            _ = try await transactionsAPI.createTransaction(
                token: token,
                description: trimmedDesc,
                amount: rawAmount,
                date: dateEpochMs,
                hasTime: hasTime,
                categoryId: category.id,
                accountId: account.id,
                type: "expense",
                installmentsEnabled: isInstallmentsEnabled && account.allowsInstallments,
                installmentsCount: installmentsCount
            )

            successFeedback = isInstallmentsEnabled
                ? "Gasto parcelado em \(installmentsCount)x cadastrado com sucesso!"
                : "Gasto cadastrado com sucesso!"
            showSuccessAlert = true
            resetForm()
            AppLogger.shared.info("Gasto registrado com sucesso: \(trimmedDesc)", category: .business)
            return true
        } catch let err as any AppErrorProtocol {
            self.activeError = err
            AppLogger.shared.error("Falha ao registrar gasto: \(err.errorDescription ?? err.localizedDescription)", category: .network)
            return false
        } catch {
            let unk = NetworkError.unknown(reason: error.localizedDescription)
            self.activeError = unk
            AppLogger.shared.error("Erro inesperado ao registrar gasto: \(error.localizedDescription)", category: .network)
            return false
        }
    }

    private func resetForm() {
        descriptionText = ""
        rawAmount = 0.0
        amountInputString = ""
        selectedDate = Date()
        isInstallmentsEnabled = false
        installmentsCount = 2
    }
}
