import SwiftUI

/// Tela de Extrato Completo de Gastos e Transações do Usuário no Cofrinho.
/// Suporta filtros avançados (Conta, Categoria, Ocultas, Período), projeção de parcelas futuras,
/// salto direto para qualquer mês/ano e ações de deslize seguras com confirmação.
public struct TransactionsListView: View {
    let token: String

    @State private var transactions: [TransactionModel] = []
    @State private var isLoading: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var canLoadMore: Bool = true
    @State private var currentPage: Int = 1
    private let pageSize: Int = 30

    // Filtros e Navegação Temporal
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedAccountId: Int? = nil
    @State private var selectedCategoryId: Int? = nil
    @State private var filterStatus: String = "active"

    // Estados de Sheets
    @State private var showNewExpenseSheet: Bool = false
    @State private var showFilterSheet: Bool = false
    @State private var showMonthYearPicker: Bool = false

    // Dados Auxiliares para Filtros
    @State private var availableAccounts: [AccountModel] = []
    @State private var availableCategories: [CategoryModel] = []

    // Estados de Exclusão e Confirmações
    @State private var transactionToDelete: TransactionModel?
    @State private var showDeleteConfirmation: Bool = false // Para parceladas (cascata)
    @State private var showSingleDeleteConfirmation: Bool = false // Para gasto único
    @State private var transactionToToggleVisibility: TransactionModel?
    @State private var showVisibilityConfirmation: Bool = false

    @State private var activeError: (any AppErrorProtocol)?

    public init(token: String) {
        self.token = token
    }

    private var hasActiveFilters: Bool {
        selectedAccountId != nil || selectedCategoryId != nil || filterStatus != "active"
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Barra de Seleção de Mês/Ano (Salto Direto)
                monthSelectorHeader

                // MARK: - Barra de Filtros Ativos (Chips)
                activeFiltersBar

                // MARK: - Card de Resumo Mensal com Projeção de Parcelas
                monthlySummaryCard

                // MARK: - Lista de Gastos
                if isLoading && transactions.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Carregando extrato...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if transactions.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(transactions) { tx in
                            transactionRow(tx)
                                .onAppear {
                                    loadMoreIfNeeded(currentItem: tx)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    // Ação Primária: Excluir com Full Swipe
                                    Button(role: .destructive) {
                                        prepareDelete(tx)
                                    } label: {
                                        Label("Excluir", systemImage: "trash.fill")
                                    }

                                    // Ação Secundária: Ocultar / Desocultar
                                    Button {
                                        prepareToggleVisibility(tx)
                                    } label: {
                                        Label(
                                            tx.status == "hidden" ? "Desocultar" : "Ocultar",
                                            systemImage: tx.status == "hidden" ? "eye.fill" : "eye.slash.fill"
                                        )
                                    }
                                    .tint(tx.status == "hidden" ? Color.blue : Color.secondary)
                                }
                        }

                        if isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 8)
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await loadTransactions(reset: true)
                    }
                }
            }
            .navigationTitle("Extrato")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(hasActiveFilters ? Color.orange : Color.blue)
                            if hasActiveFilters {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewExpenseSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.blue)
                    }
                }
            }
            // MARK: - Sheet Novo Gasto
            .sheet(isPresented: $showNewExpenseSheet) {
                NavigationStack {
                    NewExpenseView(token: token)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fechar") {
                                    showNewExpenseSheet = false
                                    Task {
                                        await loadTransactions(reset: true)
                                    }
                                }
                            }
                        }
                }
            }
            // MARK: - Sheet de Filtros Avançados
            .sheet(isPresented: $showFilterSheet) {
                TransactionsFilterSheetView(
                    selectedAccountId: $selectedAccountId,
                    selectedCategoryId: $selectedCategoryId,
                    filterStatus: $filterStatus,
                    selectedMonth: $selectedMonth,
                    selectedYear: $selectedYear,
                    accounts: availableAccounts,
                    categories: availableCategories,
                    onApply: {
                        Task {
                            await loadTransactions(reset: true)
                        }
                    }
                )
            }
            // MARK: - Sheet de Salto Direto de Mês/Ano
            .sheet(isPresented: $showMonthYearPicker) {
                MonthYearPickerSheetView(
                    selectedMonth: $selectedMonth,
                    selectedYear: $selectedYear,
                    onApply: {
                        Task {
                            await loadTransactions(reset: true)
                        }
                    }
                )
            }
            // MARK: - Confirmação: Exclusão de Gasto Único
            .alert(
                "Excluir este gasto?",
                isPresented: $showSingleDeleteConfirmation,
                presenting: transactionToDelete
            ) { tx in
                Button("Excluir Gasto", role: .destructive) {
                    Task { await performDelete(tx, cascade: "single") }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { tx in
                Text("Tem certeza de que deseja excluir \"\(tx.description)\" no valor de \(tx.formattedAmount)? O lançamento será removido do seu extrato.")
            }
            // MARK: - Confirmação: Exclusão em Cascata de Parcelas
            .confirmationDialog(
                "Excluir Gasto Parcelado",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Excluir apenas esta parcela", role: .destructive) {
                    if let tx = transactionToDelete {
                        Task { await performDelete(tx, cascade: "single") }
                    }
                }
                Button("Excluir esta e todas as futuras", role: .destructive) {
                    if let tx = transactionToDelete {
                        Task { await performDelete(tx, cascade: "all_future") }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Este gasto faz parte de um parcelamento. Deseja remover apenas a parcela atual ou também as parcelas restantes?")
            }
            // MARK: - Confirmação: Ocultar / Desocultar
            .alert(
                transactionToToggleVisibility?.status == "hidden" ? "Desocultar este gasto?" : "Ocultar este gasto?",
                isPresented: $showVisibilityConfirmation,
                presenting: transactionToToggleVisibility
            ) { tx in
                Button(tx.status == "hidden" ? "Desocultar" : "Ocultar", role: tx.status == "hidden" ? .none : .destructive) {
                    Task { await toggleVisibility(tx) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { tx in
                if tx.status == "hidden" {
                    Text("Deseja desocultar \"\(tx.description)\"? O gasto voltará a ser exibido normalmente no extrato padrão.")
                } else {
                    Text("Deseja ocultar \"\(tx.description)\"? O gasto não aparecerá no extrato padrão, mas você poderá visualizá-lo a qualquer momento ativando o filtro 'Exibir despesas ocultas'.")
                }
            }
            .handleAnyAppError($activeError)
            .task {
                await loadAuxiliaryData()
                await loadTransactions(reset: true)
            }
        }
    }

    // MARK: - Subcomponentes da UI

    private var monthSelectorHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.bold())
                    .padding(8)
            }

            Spacer()

            // Botão com Calendário que permite Salto Direto de Mês/Ano
            Button {
                showMonthYearPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.blue)

                    Text(monthYearTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Image(systemName: "chevron.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemBackground))
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
            }

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .padding(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private var activeFiltersBar: some View {
        if hasActiveFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let accId = selectedAccountId, let acc = availableAccounts.first(where: { $0.id == accId }) {
                        filterChip(title: acc.name, icon: acc.icon, color: acc.swiftUIColor) {
                            selectedAccountId = nil
                            Task { await loadTransactions(reset: true) }
                        }
                    }

                    if let catId = selectedCategoryId, let cat = availableCategories.first(where: { $0.id == catId }) {
                        filterChip(title: cat.name, icon: cat.icon, color: cat.swiftUIColor) {
                            selectedCategoryId = nil
                            Task { await loadTransactions(reset: true) }
                        }
                    }

                    if filterStatus == "all" {
                        filterChip(title: "Com Ocultas", icon: "eye.fill", color: .purple) {
                            filterStatus = "active"
                            Task { await loadTransactions(reset: true) }
                        }
                    } else if filterStatus == "hidden" {
                        filterChip(title: "Apenas Ocultas", icon: "eye.slash.fill", color: .purple) {
                            filterStatus = "active"
                            Task { await loadTransactions(reset: true) }
                        }
                    }

                    Button {
                        selectedAccountId = nil
                        selectedCategoryId = nil
                        filterStatus = "active"
                        Task { await loadTransactions(reset: true) }
                    } label: {
                        Text("Limpar Filtros")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .background(Color(.tertiarySystemBackground))
        }
    }

    private func filterChip(title: String, icon: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)

            Text(title)
                .font(.caption.weight(.semibold))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
    }

    private var monthlySummaryCard: some View {
        let regularExpenses = transactions.filter { !$0.isInstallment }
        let installmentExpenses = transactions.filter { $0.isInstallment }
        let regularTotal = regularExpenses.reduce(Decimal(0)) { $0 + $1.amount }
        let installmentTotal = installmentExpenses.reduce(Decimal(0)) { $0 + $1.amount }
        let total = regularTotal + installmentTotal

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.locale = Locale(identifier: "pt_BR")
        let totalStr = formatter.string(from: total as NSDecimalNumber) ?? "R$ 0,00"
        let regularStr = formatter.string(from: regularTotal as NSDecimalNumber) ?? "R$ 0,00"
        let installmentStr = formatter.string(from: installmentTotal as NSDecimalNumber) ?? "R$ 0,00"

        return VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(installmentTotal > 0 && regularTotal == 0 ? "Comprometido no Mês (Parcelas)" : "Total Gasto no Mês")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(totalStr)
                        .font(.title2.bold())
                        .foregroundStyle(Color.red)
                }
                Spacer()
                Image(systemName: installmentTotal > 0 ? "creditcard.and.123" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.red.opacity(0.8))
            }

            // Discriminação dos valores das parcelas nos extratos futuros
            if installmentTotal > 0 {
                Divider()
                    .padding(.vertical, 2)

                HStack(spacing: 12) {
                    if regularTotal > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "banknote")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("À vista: \(regularStr)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "creditcard")
                            .font(.caption2)
                            .foregroundStyle(Color.blue)
                        Text("Parcelas: \(installmentStr) (\(installmentExpenses.count)x)")
                            .font(.caption.bold())
                            .foregroundStyle(Color.blue)
                    }

                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func transactionRow(_ tx: TransactionModel) -> some View {
        HStack(spacing: 12) {
            // Ícone da Categoria
            ZStack {
                Circle()
                    .fill(colorFromHex(tx.category?.color ?? "#FF9500").opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: tx.category?.icon ?? "tag.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colorFromHex(tx.category?.color ?? "#FF9500"))
            }

            // Descrição e Conta
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tx.description)
                        .font(.body.weight(.medium))
                        .foregroundStyle(tx.status == "hidden" ? .secondary : .primary)

                    if let badge = tx.installmentBadge {
                        Text(badge)
                            .font(.caption2.bold())
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(6)
                    }

                    if tx.status == "hidden" {
                        HStack(spacing: 2) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 9))
                            Text("Oculto")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                    }
                }

                HStack(spacing: 6) {
                    Text(tx.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let accName = tx.account?.name {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(accName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Valor
            Text(tx.formattedAmount)
                .font(.callout.bold())
                .foregroundStyle(tx.status == "hidden" ? Color.secondary : Color.red)
        }
        .padding(.vertical, 4)
        .opacity(tx.status == "hidden" ? 0.75 : 1.0)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "tray.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.gray.opacity(0.6))

            Text(hasActiveFilters ? "Nenhum gasto com os filtros atuais" : "Nenhum gasto neste mês")
                .font(.headline)

            Text(hasActiveFilters ? "Tente redefinir os filtros ou alterar o mês para encontrar transações." : "Toque no botão abaixo para adicionar seu primeiro gasto.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if hasActiveFilters {
                Button {
                    selectedAccountId = nil
                    selectedCategoryId = nil
                    filterStatus = "active"
                    Task { await loadTransactions(reset: true) }
                } label: {
                    Text("Limpar Filtros")
                        .font(.headline)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
            } else {
                Button {
                    showNewExpenseSheet = true
                } label: {
                    Text("+ Adicionar Gasto")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
            Spacer()
        }
    }

    // MARK: - Lógicas de Ação

    private var monthYearTitle: String {
        var components = DateComponents()
        components.month = selectedMonth
        components.year = selectedYear
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: date).capitalized
    }

    private func changeMonth(by delta: Int) {
        var month = selectedMonth + delta
        var year = selectedYear
        while month > 12 {
            month -= 12
            year += 1
        }
        while month < 1 {
            month += 12
            year -= 1
        }
        selectedMonth = month
        selectedYear = year
        Task {
            await loadTransactions(reset: true)
        }
    }

    private func loadAuxiliaryData() async {
        // Carrega do cache instantâneo
        let cachedAccs = LocalDataManager.shared.fetchCachedAccounts()
        if !cachedAccs.isEmpty { availableAccounts = cachedAccs }

        let cachedCats = LocalDataManager.shared.fetchCachedCategories()
        if !cachedCats.isEmpty { availableCategories = cachedCats }

        // Sincroniza em segundo plano com a VPS
        do {
            let accs = try await AccountsAPIService.shared.listAccounts(token: token)
            self.availableAccounts = accs
            LocalDataManager.shared.cacheAccounts(accs)
        } catch {
            AppLogger.shared.warning("Falha ao carregar contas para filtro: \(error.localizedDescription)", category: .network)
        }

        do {
            let cats = try await CategoriesAPIService.shared.listCategories(token: token)
            self.availableCategories = cats
            LocalDataManager.shared.cacheCategories(cats)
        } catch {
            AppLogger.shared.warning("Falha ao carregar categorias para filtro: \(error.localizedDescription)", category: .network)
        }
    }

    private func loadTransactions(reset: Bool = true) async {
        if reset {
            currentPage = 1
            canLoadMore = true
            // 1. Carrega instantaneamente o cache local do SwiftData para 0 delay na UI
            let cached = LocalDataManager.shared.fetchCachedTransactions(
                month: selectedMonth,
                year: selectedYear,
                categoryId: selectedCategoryId,
                accountId: selectedAccountId,
                status: filterStatus
            )
            if !cached.isEmpty {
                self.transactions = cached
            }
        }

        isLoading = reset && transactions.isEmpty
        defer { isLoading = false }

        // 2. Sincroniza em segundo plano pendências locais criadas offline
        Task {
            await LocalDataManager.shared.syncPendingTransactions(token: token)
        }

        do {
            let fetched = try await TransactionsAPIService.shared.listTransactions(
                token: token,
                month: selectedMonth,
                year: selectedYear,
                categoryId: selectedCategoryId,
                accountId: selectedAccountId,
                status: filterStatus,
                page: currentPage,
                limit: pageSize
            )

            if fetched.count < pageSize {
                canLoadMore = false
            }

            if reset {
                transactions = fetched
            } else {
                transactions.append(contentsOf: fetched)
            }

            LocalDataManager.shared.cacheTransactions(fetched)
            AppLogger.shared.info("Extrato atualizado (\(transactions.count) transações, status: \(filterStatus)).", category: .business)
        } catch let err as any AppErrorProtocol {
            // Se offline e temos dados em cache, opera silenciosamente
            if !transactions.isEmpty && isConnectionError(err) {
                AppLogger.shared.info("Falha de conexão com a VPS. Mantendo extrato visível via cache SwiftData.", category: .network)
            } else {
                self.activeError = err
                AppLogger.shared.error("Erro ao carregar extrato: \(err.errorDescription ?? err.localizedDescription)", category: .network)
            }
        } catch {
            let unk = NetworkError.unknown(reason: error.localizedDescription)
            self.activeError = unk
            AppLogger.shared.error("Erro ao carregar extrato: \(error.localizedDescription)", category: .network)
        }
    }

    private func loadMoreIfNeeded(currentItem: TransactionModel) {
        guard let lastItem = transactions.last,
              lastItem.id == currentItem.id,
              canLoadMore,
              !isLoading,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true
        currentPage += 1

        Task {
            defer { isLoadingMore = false }
            do {
                let fetched = try await TransactionsAPIService.shared.listTransactions(
                    token: token,
                    month: selectedMonth,
                    year: selectedYear,
                    categoryId: selectedCategoryId,
                    accountId: selectedAccountId,
                    status: filterStatus,
                    page: currentPage,
                    limit: pageSize
                )

                if fetched.count < pageSize {
                    canLoadMore = false
                }

                transactions.append(contentsOf: fetched)
                LocalDataManager.shared.cacheTransactions(fetched)
                AppLogger.shared.info("Página \(currentPage) carregada com +\(fetched.count) gastos.", category: .business)
            } catch {
                canLoadMore = false
            }
        }
    }

    private func isConnectionError(_ error: any AppErrorProtocol) -> Bool {
        if let netErr = error as? NetworkError {
            switch netErr {
            case .noConnection, .serverUnreachable, .timeout:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func prepareDelete(_ tx: TransactionModel) {
        transactionToDelete = tx
        if tx.isInstallment && (tx.totalInstallments ?? 1) > 1 {
            showDeleteConfirmation = true
        } else {
            showSingleDeleteConfirmation = true
        }
    }

    private func prepareToggleVisibility(_ tx: TransactionModel) {
        transactionToToggleVisibility = tx
        showVisibilityConfirmation = true
    }

    private func performDelete(_ tx: TransactionModel, cascade: String) async {
        do {
            try await TransactionsAPIService.shared.deleteTransaction(
                token: token,
                id: tx.id,
                cascade: cascade
            )
            AppLogger.shared.info("Transação \(tx.id) excluída com sucesso (modo: \(cascade)).", category: .business)
            await loadTransactions(reset: true)
        } catch let err as any AppErrorProtocol {
            self.activeError = err
            AppLogger.shared.error("Erro ao excluir gasto: \(err.errorDescription ?? err.localizedDescription)", category: .network)
        } catch {
            let unk = NetworkError.unknown(reason: error.localizedDescription)
            self.activeError = unk
            AppLogger.shared.error("Erro ao excluir gasto: \(error.localizedDescription)", category: .network)
        }
    }

    private func toggleVisibility(_ tx: TransactionModel) async {
        do {
            _ = try await TransactionsAPIService.shared.toggleVisibility(token: token, id: tx.id)
            AppLogger.shared.info("Visibilidade alternada para transação \(tx.id).", category: .business)
            await loadTransactions(reset: true)
        } catch let err as any AppErrorProtocol {
            self.activeError = err
            AppLogger.shared.error("Erro ao alternar visibilidade: \(err.errorDescription ?? err.localizedDescription)", category: .network)
        } catch {
            let unk = NetworkError.unknown(reason: error.localizedDescription)
            self.activeError = unk
            AppLogger.shared.error("Erro ao alternar visibilidade: \(error.localizedDescription)", category: .network)
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 149, 0)
        }
        return Color(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1.0)
    }
}
