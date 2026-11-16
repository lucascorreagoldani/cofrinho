import SwiftUI

/// Tela de Extrato Completo de Gastos e Transações do Usuário no Cofrinho.
/// Suporta navegação inteligente por dias com lançamentos via deslize lateral fluido,
/// filtros avançados via Enums, projeção de parcelas futuras, detalhes expansíveis por lançamento,
/// salto direto para qualquer mês/ano e sincronização offline com SwiftData.
public struct TransactionsListView: View {
    let token: String

    @State private var transactions: [TransactionModel] = []
    @State private var isLoading: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var isFetchingNetwork: Bool = false
    @State private var activeFetchToken: UUID = UUID()
    @State private var canLoadMore: Bool = false
    @State private var currentPage: Int = 1
    private let pageSize: Int = 30

    // Filtros e Navegação Temporal
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedDay: Int? = Calendar.current.component(.day, from: Date())
    @State private var lastSwipeTimestamp: TimeInterval = 0
    @State private var selectedAccountId: Int? = nil
    @State private var selectedCategoryId: Int? = nil
    @State private var filterStatus: TransactionFilterStatus = .active

    // Estados de Sheets e Detalhes
    @State private var showNewExpenseSheet: Bool = false
    @State private var showFilterSheet: Bool = false
    @State private var showMonthYearPicker: Bool = false
    @State private var selectedTransactionForDetail: TransactionModel? = nil

    // Dados Auxiliares para Filtros
    @State private var availableAccounts: [AccountModel] = []
    @State private var availableCategories: [CategoryModel] = []

    // Estados de Exclusão e Confirmações
    @State private var transactionToDelete: TransactionModel?
    @State private var showDeleteConfirmation: Bool = false
    @State private var showSingleDeleteConfirmation: Bool = false
    @State private var transactionToToggleVisibility: TransactionModel?
    @State private var showVisibilityConfirmation: Bool = false

    @State private var activeError: (any AppErrorProtocol)?

    public init(token: String) {
        self.token = token
    }

    private var hasActiveFilters: Bool {
        selectedAccountId != nil || selectedCategoryId != nil || filterStatus != .active
    }

    private var isCurrentMonthAndYear: Bool {
        let now = Date()
        let curMonth = Calendar.current.component(.month, from: now)
        let curYear = Calendar.current.component(.year, from: now)
        return selectedMonth == curMonth && selectedYear == curYear
    }

    private var todayDay: Int {
        Calendar.current.component(.day, from: Date())
    }

    private var isViewingToday: Bool {
        isCurrentMonthAndYear && selectedDay == todayDay
    }

    private var availableTransactionDays: [Int] {
        let calendar = Calendar.current
        let days = transactions.map { calendar.component(.day, from: $0.dateValue) }
        return Array(Set(days)).sorted()
    }

    private var selectableDays: [Int] {
        var days = availableTransactionDays
        if isCurrentMonthAndYear {
            days.append(todayDay)
        }
        return Array(Set(days)).sorted()
    }

    private var displayedTransactions: [TransactionModel] {
        guard let selectedDay else { return transactions }
        let calendar = Calendar.current
        return transactions.filter { calendar.component(.day, from: $0.dateValue) == selectedDay }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Bloco superior unificado com gesto fluido horizontal para troca rápida de dia/mês
                VStack(spacing: 0) {
                    // MARK: - Barra de Seleção de Mês/Ano (Sem botão Hoje duplicado)
                    monthSelectorHeader

                    // MARK: - Barra Interativa de Salto Inteligente por Dias com Lançamentos
                    dayNavigationBar

                    // MARK: - Barra de Filtros Ativos (Chips)
                    activeFiltersBar

                    // MARK: - Card de Resumo (Dia ou Mês) com Projeção de Parcelas
                    monthlySummaryCard
                }
                .contentShape(Rectangle())
                .simultaneousGesture(horizontalDaySwipeGesture)

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(horizontalDaySwipeGesture)
                } else if displayedTransactions.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .simultaneousGesture(horizontalDaySwipeGesture)
                } else {
                    List {
                        ForEach(displayedTransactions) { tx in
                            Button {
                                selectedTransactionForDetail = tx
                            } label: {
                                transactionRow(tx)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
                                    let isHidden = tx.statusEnum == .hidden
                                    Label(
                                        isHidden ? "Desocultar" : "Ocultar",
                                        systemImage: isHidden ? "eye.fill" : "eye.slash.fill"
                                    )
                                }
                                .tint(tx.statusEnum == .hidden ? Color.blue : Color.secondary)
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

                        // Área ampla de respiro inferior para deslize horizontal fluido sem tocar em células
                        Section {
                            VStack(spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.left.and.right")
                                        .font(.caption2)
                                    Text("Deslize para navegar entre dias com lançamentos")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.tertiary)
                                .padding(.top, 12)

                                Spacer(minLength: 260)
                            }
                            .frame(maxWidth: .infinity, minHeight: 300)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                        }
                    }
                    .listStyle(.insetGrouped)
                    .simultaneousGesture(horizontalDaySwipeGesture)
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

                if !isViewingToday {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            goToToday()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.clock")
                                Text("Hoje")
                                    .font(.caption.bold())
                            }
                            .foregroundStyle(Color.blue)
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
            // MARK: - Sheet de Detalhes do Lançamento e Parcelamento
            .sheet(item: $selectedTransactionForDetail) { tx in
                TransactionDetailSheetView(
                    transaction: tx,
                    token: token,
                    onUpdated: {
                        Task {
                            await loadTransactions(reset: true)
                        }
                    }
                )
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
                        selectedDay = nil
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
                        selectedDay = nil
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
                    Task { await performDelete(tx, cascade: .single) }
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
                        Task { await performDelete(tx, cascade: .single) }
                    }
                }
                Button("Excluir esta e todas as futuras", role: .destructive) {
                    if let tx = transactionToDelete {
                        Task { await performDelete(tx, cascade: .allFuture) }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Este gasto faz parte de um parcelamento. Deseja remover apenas a parcela atual ou também as parcelas restantes?")
            }
            // MARK: - Confirmação: Ocultar / Desocultar
            .alert(
                transactionToToggleVisibility?.statusEnum == .hidden ? "Desocultar este gasto?" : "Ocultar este gasto?",
                isPresented: $showVisibilityConfirmation,
                presenting: transactionToToggleVisibility
            ) { tx in
                let isHidden = tx.statusEnum == .hidden
                Button(isHidden ? "Desocultar" : "Ocultar", role: isHidden ? .none : .destructive) {
                    Task { await toggleVisibility(tx) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { tx in
                if tx.statusEnum == .hidden {
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
        HStack(spacing: 8) {
            Button {
                changeMonthWithAnimation(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.bold())
                    .padding(8)
            }

            Spacer()

            // Botão com Calendário que permite Salto Direto de Mês/Ano (botão Hoje fica apenas na topBarTrailing)
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
                .clipShape(.rect(cornerRadius: 20))
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
            }

            Spacer()

            Button {
                changeMonthWithAnimation(by: 1)
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

    private var dayNavigationBar: some View {
        HStack(spacing: 6) {
            Button {
                navigateDaySmart(direction: -1)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.blue.opacity(0.85))
            }
            .buttonStyle(.plain)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDay = nil
                            }
                        } label: {
                            Text("Mês Inteiro")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedDay == nil ? Color.blue : Color(.systemBackground))
                                .foregroundStyle(selectedDay == nil ? Color.white : Color.primary)
                                .clipShape(.rect(cornerRadius: 16))
                                .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
                        }
                        .id(-1)
                        .buttonStyle(.plain)

                        ForEach(selectableDays, id: \.self) { day in
                            let isTodayChip = isCurrentMonthAndYear && day == todayDay
                            Button {
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedDay = (selectedDay == day) ? nil : day
                                }
                            } label: {
                                Text(isTodayChip ? String(format: "Hoje (%02d)", day) : String(format: "Dia %02d", day))
                                    .font(.caption.bold().monospacedDigit())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedDay == day ? Color.blue : Color(.systemBackground))
                                    .foregroundStyle(selectedDay == day ? Color.white : Color.primary)
                                    .clipShape(.rect(cornerRadius: 16))
                                    .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
                            }
                            .id(day)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    proxy.scrollTo(selectedDay ?? -1, anchor: .center)
                }
                .onChange(of: selectedDay) { _, newDay in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(newDay ?? -1, anchor: .center)
                    }
                }
            }

            Button {
                navigateDaySmart(direction: 1)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.blue.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
    }

    @ViewBuilder
    private var activeFiltersBar: some View {
        if hasActiveFilters {
            ScrollView(.horizontal) {
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

                    if filterStatus == .all {
                        filterChip(title: "Com Ocultas", icon: "eye.fill", color: .purple) {
                            filterStatus = .active
                            Task { await loadTransactions(reset: true) }
                        }
                    } else if filterStatus == .hidden {
                        filterChip(title: "Apenas Ocultas", icon: "eye.slash.fill", color: .purple) {
                            filterStatus = .active
                            Task { await loadTransactions(reset: true) }
                        }
                    }

                    Button {
                        selectedAccountId = nil
                        selectedCategoryId = nil
                        filterStatus = .active
                        Task { await loadTransactions(reset: true) }
                    } label: {
                        Text("Limpar Filtros")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
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
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
    }

    private var monthlySummaryCard: some View {
        let targetItems = displayedTransactions
        let regularExpenses = targetItems.filter { !$0.isInstallment }
        let installmentExpenses = targetItems.filter { $0.isInstallment }
        let regularTotal = regularExpenses.reduce(Decimal(0)) { $0 + $1.amount }
        let installmentTotal = installmentExpenses.reduce(Decimal(0)) { $0 + $1.amount }
        let total = regularTotal + installmentTotal

        let summaryLabel: String = {
            if let day = selectedDay {
                return String(format: "Total no Dia %02d/%02d", day, selectedMonth)
            }
            if installmentTotal > 0 && regularTotal == 0 {
                return "Comprometido no Mês (Parcelas)"
            }
            return "Total Gasto no Mês"
        }()

        return VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(total.brlCurrencyFormatted)
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
                            Text("À vista: \(regularTotal.brlCurrencyFormatted)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "creditcard")
                            .font(.caption2)
                            .foregroundStyle(Color.blue)
                        Text("Parcelas: \(installmentTotal.brlCurrencyFormatted) (\(installmentExpenses.count)x)")
                            .font(.caption.bold())
                            .foregroundStyle(Color.blue)
                    }

                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func transactionRow(_ tx: TransactionModel) -> some View {
        let isHidden = tx.statusEnum == .hidden
        let categoryColor = Color(hex: tx.category?.color ?? "#FF9500")
        let hasNotes = !(tx.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        return HStack(spacing: 12) {
            // Ícone da Categoria
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: tx.category?.icon ?? "tag.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(categoryColor)
            }

            // Descrição e Conta
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tx.description)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isHidden ? .secondary : .primary)
                        .lineLimit(1)

                    if let badge = tx.installmentBadge {
                        Text(badge)
                            .font(.caption2.bold())
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(.rect(cornerRadius: 6))
                    }

                    if hasNotes {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(Color.blue.opacity(0.8))
                    }

                    if isHidden {
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
                        .clipShape(.rect(cornerRadius: 4))
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
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Valor + Indicador de expansão de detalhes
            HStack(spacing: 6) {
                Text(tx.formattedAmount)
                    .font(.callout.bold())
                    .foregroundStyle(isHidden ? Color.secondary : Color.red)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .opacity(isHidden ? 0.75 : 1.0)
    }

    private var emptyStateView: some View {
        let emptyTitle: String = {
            if hasActiveFilters {
                return "Nenhum gasto com os filtros atuais"
            }
            if let day = selectedDay {
                if isCurrentMonthAndYear && day == todayDay {
                    return String(format: "Nenhum gasto hoje (%02d/%02d)", day, selectedMonth)
                }
                return String(format: "Nenhum gasto no Dia %02d/%02d", day, selectedMonth)
            }
            return "Nenhum gasto neste mês"
        }()

        let emptySubtitle: String = {
            if hasActiveFilters {
                return "Tente redefinir os filtros ou deslize para os lados para navegar entre os dias e meses."
            }
            if selectedDay != nil {
                return "Deslize para os lados para ver outros dias, toque em 'Mês Inteiro' ou adicione um novo gasto."
            }
            return "Toque no botão abaixo para adicionar seu primeiro gasto ou deslize para os lados para navegar."
        }()

        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "tray.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.gray.opacity(0.6))

            Text(emptyTitle)
                .font(.headline)

            Text(emptySubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if hasActiveFilters {
                Button {
                    selectedAccountId = nil
                    selectedCategoryId = nil
                    filterStatus = .active
                    selectedDay = nil
                    Task { await loadTransactions(reset: true) }
                } label: {
                    Text("Limpar Filtros")
                        .font(.headline)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 12))
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
                        .clipShape(.rect(cornerRadius: 12))
                }
                .padding(.top, 8)
            }
            Spacer()
        }
    }

    // MARK: - Lógicas de Ação e Navegação Inteligente por Datas

    private var monthYearTitle: String {
        let monthName = Month(rawValue: selectedMonth)?.localizedName() ?? ""
        return "\(monthName) \(selectedYear)"
    }

    /// Navegação inteligente por dia estritamente dentro dos chips do mês atual (`Mês Inteiro <-> Dias com Gastos`):
    /// - Debounce de 0.25s impede que um único arrasto execute dois saltos seguidos.
    /// - Avançar (> 0): Mês Inteiro -> 1º dia com lançamento -> próximos dias -> Mês Inteiro.
    /// - Voltar (< 0): Mês Inteiro -> último dia com lançamento -> dias anteriores -> Mês Inteiro.
    private func navigateDaySmart(direction: Int) {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastSwipeTimestamp > 0.25 else { return }
        lastSwipeTimestamp = now

        let sortedDays = selectableDays
        guard !sortedDays.isEmpty else { return }

        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()

        withAnimation(.easeInOut(duration: 0.22)) {
            if let currentDay = selectedDay {
                if direction > 0 {
                    selectedDay = sortedDays.first(where: { $0 > currentDay })
                } else {
                    selectedDay = sortedDays.last(where: { $0 < currentDay })
                }
            } else {
                if direction > 0 {
                    selectedDay = sortedDays.first
                } else {
                    selectedDay = sortedDays.last
                }
            }
        }
    }

    private func changeMonth(by delta: Int, resetSelectedDay: Bool = true) {
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
        if resetSelectedDay {
            selectedDay = nil
        }
        Task {
            await loadTransactions(reset: true)
        }
    }

    private func changeMonthWithAnimation(by delta: Int) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        withAnimation(.easeInOut(duration: 0.25)) {
            changeMonth(by: delta, resetSelectedDay: true)
        }
    }

    private func goToToday() {
        let now = Date()
        let curMonth = Calendar.current.component(.month, from: now)
        let curYear = Calendar.current.component(.year, from: now)
        let curDay = Calendar.current.component(.day, from: now)

        let monthChanged = (selectedMonth != curMonth || selectedYear != curYear)
        guard monthChanged || selectedDay != curDay else { return }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        withAnimation(.easeInOut(duration: 0.25)) {
            selectedMonth = curMonth
            selectedYear = curYear
            selectedDay = curDay
        }

        if monthChanged {
            Task {
                await loadTransactions(reset: true)
            }
        }
    }

    /// Gesto horizontal bidirecional altamente responsivo para navegação inteligente entre dias com lançamentos.
    private var horizontalDaySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.25 && abs(horizontal) > 45 else {
                    return
                }
                if horizontal < 0 {
                    navigateDaySmart(direction: 1)
                } else {
                    navigateDaySmart(direction: -1)
                }
            }
    }

    private func clearInvalidSelectedDayIfNeeded() {
        if let currentDay = selectedDay, !selectableDays.contains(currentDay) {
            selectedDay = isCurrentMonthAndYear ? todayDay : nil
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

    private func loadTransactionsFromLocalCache() {
        self.transactions = LocalDataManager.shared.fetchCachedTransactions(
            month: selectedMonth,
            year: selectedYear,
            categoryId: selectedCategoryId,
            accountId: selectedAccountId,
            status: filterStatus
        )
    }

    private func loadTransactions(reset: Bool = true) async {
        let fetchToken = UUID()
        activeFetchToken = fetchToken
        let pageToFetch = reset ? 1 : currentPage

        if reset {
            currentPage = 1
            // Mantém canLoadMore desativado durante o carregamento para impedir disparo prematuro de página 2
            canLoadMore = false
            // 1. Carrega instantaneamente o cache local do SwiftData para 0 delay na UI
            loadTransactionsFromLocalCache()
        }

        isLoading = reset && transactions.isEmpty
        isFetchingNetwork = true
        defer {
            if activeFetchToken == fetchToken {
                isLoading = false
                isFetchingNetwork = false
            }
        }

        // 2. Sincroniza em segundo plano todas as operações offline pendentes (create/update/delete)
        await LocalDataManager.shared.syncPendingTransactions(token: token)
        guard activeFetchToken == fetchToken else { return }

        do {
            let fetched = try await TransactionsAPIService.shared.listTransactions(
                token: token,
                month: selectedMonth,
                year: selectedYear,
                categoryId: selectedCategoryId,
                accountId: selectedAccountId,
                status: filterStatus,
                page: pageToFetch,
                limit: pageSize
            )

            guard activeFetchToken == fetchToken else { return }

            canLoadMore = fetched.count >= pageSize

            if reset {
                transactions = fetched
                clearInvalidSelectedDayIfNeeded()
            } else {
                transactions.append(contentsOf: fetched)
            }

            LocalDataManager.shared.cacheTransactions(fetched)
            AppLogger.shared.info("Extrato atualizado (\(transactions.count) transações, status: \(filterStatus.rawValue)).", category: .business)
        } catch let err as any AppErrorProtocol {
            guard activeFetchToken == fetchToken else { return }
            // Se offline e temos dados em cache ou fallback offline, opera silenciosamente
            if isConnectionError(err) {
                loadTransactionsFromLocalCache()
                if reset {
                    clearInvalidSelectedDayIfNeeded()
                }
                AppLogger.shared.info("Falha de conexão com a VPS. Mantendo extrato visível via cache SwiftData.", category: .network)
            } else {
                self.activeError = err
                AppLogger.shared.error("Erro ao carregar extrato: \(err.errorDescription ?? err.localizedDescription)", category: .network)
            }
        } catch {
            guard activeFetchToken == fetchToken else { return }
            let unk = NetworkError.unknown(reason: error.localizedDescription)
            self.activeError = unk
            AppLogger.shared.error("Erro ao carregar extrato: \(error.localizedDescription)", category: .network)
        }
    }

    private func loadMoreIfNeeded(currentItem: TransactionModel) {
        guard let lastDisplayed = displayedTransactions.last,
              (lastDisplayed.id == currentItem.id || transactions.last?.id == currentItem.id),
              transactions.count >= pageSize,
              canLoadMore,
              !isLoading,
              !isLoadingMore,
              !isFetchingNetwork else {
            return
        }

        isLoadingMore = true
        let nextPage = currentPage + 1
        currentPage = nextPage
        let expectedMonth = selectedMonth
        let expectedYear = selectedYear
        let expectedToken = activeFetchToken

        Task {
            defer { isLoadingMore = false }
            do {
                let fetched = try await TransactionsAPIService.shared.listTransactions(
                    token: token,
                    month: expectedMonth,
                    year: expectedYear,
                    categoryId: selectedCategoryId,
                    accountId: selectedAccountId,
                    status: filterStatus,
                    page: nextPage,
                    limit: pageSize
                )

                guard activeFetchToken == expectedToken,
                      selectedMonth == expectedMonth,
                      selectedYear == expectedYear else {
                    return
                }

                canLoadMore = fetched.count >= pageSize

                transactions.append(contentsOf: fetched)
                LocalDataManager.shared.cacheTransactions(fetched)
                AppLogger.shared.info("Página \(nextPage) carregada com +\(fetched.count) gastos.", category: .business)
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

    private func performDelete(_ tx: TransactionModel, cascade: DeleteCascadeMode) async {
        // Caso o lançamento só exista offline (id negativo), remove localmente sem chamada de rede
        if tx.id < 0 {
            LocalDataManager.shared.markOfflineDelete(id: tx.id, cascade: cascade)
            loadTransactionsFromLocalCache()
            clearInvalidSelectedDayIfNeeded()
            return
        }

        do {
            try await TransactionsAPIService.shared.deleteTransaction(
                token: token,
                id: tx.id,
                cascade: cascade
            )
            LocalDataManager.shared.removeSyncedTransaction(id: tx.id, cascade: cascade)
            AppLogger.shared.info("Transação \(tx.id) excluída com sucesso (modo: \(cascade.rawValue)).", category: .business)
            await loadTransactions(reset: true)
        } catch let err as any AppErrorProtocol where isConnectionError(err) {
            LocalDataManager.shared.markOfflineDelete(id: tx.id, cascade: cascade)
            loadTransactionsFromLocalCache()
            clearInvalidSelectedDayIfNeeded()
            AppLogger.shared.warning("Sem conexão: exclusão de \(tx.id) agendada na fila offline.", category: .database)
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
        // Caso o lançamento só exista offline (id negativo), alterna localmente
        if tx.id < 0 {
            LocalDataManager.shared.markOfflineToggleVisibility(id: tx.id)
            loadTransactionsFromLocalCache()
            clearInvalidSelectedDayIfNeeded()
            return
        }

        do {
            let updated = try await TransactionsAPIService.shared.toggleVisibility(token: token, id: tx.id)
            LocalDataManager.shared.cacheTransactions([updated])
            AppLogger.shared.info("Visibilidade alternada para transação \(tx.id).", category: .business)
            await loadTransactions(reset: true)
        } catch let err as any AppErrorProtocol where isConnectionError(err) {
            LocalDataManager.shared.markOfflineToggleVisibility(id: tx.id)
            loadTransactionsFromLocalCache()
            clearInvalidSelectedDayIfNeeded()
            AppLogger.shared.warning("Sem conexão: alteração de visibilidade de \(tx.id) agendada na fila offline.", category: .database)
        } catch let err as any AppErrorProtocol {
            self.activeError = err
            AppLogger.shared.error("Erro ao alternar visibilidade: \(err.errorDescription ?? err.localizedDescription)", category: .network)
        } catch {
            let unk = NetworkError.unknown(reason: error.localizedDescription)
            self.activeError = unk
            AppLogger.shared.error("Erro ao alternar visibilidade: \(error.localizedDescription)", category: .network)
        }
    }
}
