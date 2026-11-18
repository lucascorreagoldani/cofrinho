import SwiftUI
import Charts

/// Barra de navegação inferior (Tab Bar) principal do Cofrinho.
/// Organizada em 5 abas: Início | Extrato | Lançamento | Objetivos | Perfil.
public struct MainTabView: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: TabItem = .home
    @State private var showMoneyTipSuggestion: Bool = false
    @State private var pendingQuickLaunchType: TransactionType? = nil

    public enum TabItem: Hashable {
        case home
        case transactions
        case launch
        case goals
        case profile
    }

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
    }

    private var overlayAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.42, bounce: 0.16)
    }

    public var body: some View {
        let preferredType = viewModel.currentPreferences?.defaultTransactionTypeEnum ?? .expense

        return TabView(selection: $selectedTab) {
            // MARK: - 1. Aba Início (Hub Principal)
            HomeHubView(
                token: viewModel.token ?? "",
                userId: viewModel.currentUser?.id ?? 0,
                defaultTransactionType: preferredType,
                isSelected: selectedTab == .home,
                showMoneyTipSuggestion: $showMoneyTipSuggestion,
                pendingQuickLaunchType: $pendingQuickLaunchType
            )
            .tabItem {
                Label("Início", systemImage: "house.fill")
            }
            .tag(TabItem.home)

            // MARK: - 2. Aba Extrato (Lista Completa de Lançamentos, Filtro e Parcelas)
            TransactionsListView(
                token: viewModel.token ?? "",
                defaultTransactionType: preferredType
            )
            .tabItem {
                Label("Extrato", systemImage: "list.bullet.rectangle.portrait.fill")
            }
            .tag(TabItem.transactions)

            // MARK: - 3. Aba Lançamento (Cadastro Rápido de Gasto ou Receita)
            NavigationStack {
                NewExpenseView(
                    token: viewModel.token ?? "",
                    defaultType: preferredType
                )
            }
            .tabItem {
                Label("Lançamento", systemImage: "plus.circle.fill")
            }
            .tag(TabItem.launch)

            // MARK: - 4. Aba Objetivos (Cofrinhos Inteligentes)
            NavigationStack {
                VStack(spacing: 16) {
                    Image(systemName: "target")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.green)
                    Text("Cofrinhos & Objetivos")
                        .font(.title2.bold())
                    Text("Em breve: Acompanhamento das suas metas e objetivos financeiros.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .navigationTitle("Objetivos")
            }
            .tabItem {
                Label("Objetivos", systemImage: "target")
            }
            .tag(TabItem.goals)

            // MARK: - 5. Aba Perfil
            ProfileView(viewModel: viewModel)
                .tabItem {
                    Label("Perfil", systemImage: "person.crop.circle.fill")
                }
                .tag(TabItem.profile)
        }
        .tint(Color.blue)
        .blur(radius: showMoneyTipSuggestion ? 14 : 0)
        .scaleEffect(showMoneyTipSuggestion ? 0.97 : 1.0)
        .allowsHitTesting(!showMoneyTipSuggestion)
        .animation(overlayAnimation, value: showMoneyTipSuggestion)
        .overlay {
            if showMoneyTipSuggestion {
                MoneyTipSpotlightOverlay(
                    onSelectType: { selectedType in
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0.12)) {
                            showMoneyTipSuggestion = false
                        }
                        pendingQuickLaunchType = selectedType
                    },
                    onDismiss: {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.34, bounce: 0.12)) {
                            showMoneyTipSuggestion = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .zIndex(100)
            }
        }
        .animation(overlayAnimation, value: showMoneyTipSuggestion)
    }
}

/// Hub principal na aba Início com atalho de Novo Lançamento, saldo "Meu dinheiro",
/// sugestão interativa única por conta (?) e comparativo visual Gastos x Receita.
public struct HomeHubView: View {
    private enum ChartScope: String, CaseIterable, Identifiable {
        case total = "Geral"
        case currentMonth = "Este Mês"

        var id: String { rawValue }
    }

    private struct CashflowBarPoint: Identifiable {
        let id: String
        let label: String
        let amount: Double
        let color: Color
    }

    private struct LaunchSheetRequest: Identifiable {
        let id = UUID()
        let initialType: TransactionType
    }

    let token: String
    let userId: Int
    let defaultTransactionType: TransactionType
    let isSelected: Bool

    @Binding var showMoneyTipSuggestion: Bool
    @Binding var pendingQuickLaunchType: TransactionType?

    @State private var transactions: [TransactionModel] = []
    @State private var isLoading: Bool = false
    @State private var chartScope: ChartScope = .total

    @State private var hasDismissedHelpButton: Bool

    @State private var launchSheetRequest: LaunchSheetRequest? = nil
    @State private var didCreateTransactionInSheet: Bool = false

    public init(
        token: String,
        userId: Int = 0,
        defaultTransactionType: TransactionType = .expense,
        isSelected: Bool = true,
        showMoneyTipSuggestion: Binding<Bool> = .constant(false),
        pendingQuickLaunchType: Binding<TransactionType?> = .constant(nil)
    ) {
        self.token = token
        self.userId = userId
        self.defaultTransactionType = defaultTransactionType
        self.isSelected = isSelected
        self._showMoneyTipSuggestion = showMoneyTipSuggestion
        self._pendingQuickLaunchType = pendingQuickLaunchType
        let dismissed = UserDefaults.standard.bool(forKey: AuthViewModel.homeMoneyTipDismissedKey(for: userId))
        self._hasDismissedHelpButton = State(initialValue: dismissed)
    }

    private var allIncomeTotal: Double {
        transactions
            .filter { $0.typeEnum == .income }
            .reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.amount).doubleValue }
    }

    private var allExpenseTotal: Double {
        transactions
            .filter { $0.typeEnum == .expense }
            .reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.amount).doubleValue }
    }

    private var availableBalance: Double {
        allIncomeTotal - allExpenseTotal
    }

    private var scopedTransactions: [TransactionModel] {
        switch chartScope {
        case .total:
            return transactions
        case .currentMonth:
            let now = Date()
            let calendar = Calendar.current
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            return transactions.filter { tx in
                let comps = calendar.dateComponents([.month, .year], from: tx.dateValue)
                return comps.month == currentMonth && comps.year == currentYear
            }
        }
    }

    private var scopedIncomeTotal: Double {
        scopedTransactions
            .filter { $0.typeEnum == .income }
            .reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.amount).doubleValue }
    }

    private var scopedExpenseTotal: Double {
        scopedTransactions
            .filter { $0.typeEnum == .expense }
            .reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.amount).doubleValue }
    }

    private var chartPoints: [CashflowBarPoint] {
        [
            CashflowBarPoint(id: "income", label: "Receitas", amount: scopedIncomeTotal, color: .green),
            CashflowBarPoint(id: "expense", label: "Gastos", amount: scopedExpenseTotal, color: .red)
        ]
    }

    private var chartMaxDomain: Double {
        let highest = max(scopedIncomeTotal, scopedExpenseTotal, 100.0)
        return highest * 1.28
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    launchHeroButton
                    myMoneyCard
                    incomeVsExpenseChartCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .refreshable {
                await loadSummaryData()
            }
            .navigationTitle("Início")
            .navigationBarTitleDisplayMode(.large)
            .task {
                syncHelpFlagForCurrentUser()
                await loadSummaryData()
            }
            .onChange(of: isSelected) { _, nowSelected in
                if nowSelected {
                    syncHelpFlagForCurrentUser()
                    Task {
                        await loadSummaryData()
                    }
                }
            }
            .onChange(of: userId) { _, _ in
                syncHelpFlagForCurrentUser()
                showMoneyTipSuggestion = false
                Task {
                    await loadSummaryData()
                }
            }
            .onChange(of: pendingQuickLaunchType) { _, newType in
                guard let newType else { return }
                pendingQuickLaunchType = nil
                openLaunchSheet(with: newType)
            }
            .sheet(
                item: $launchSheetRequest,
                onDismiss: {
                    guard didCreateTransactionInSheet else { return }
                    didCreateTransactionInSheet = false
                    Task {
                        await loadSummaryData()
                    }
                }
            ) { request in
                NavigationStack {
                    NewExpenseView(
                        token: token,
                        initialDate: Date(),
                        defaultType: request.initialType,
                        onSaved: {
                            didCreateTransactionInSheet = true
                            launchSheetRequest = nil
                        }
                    )
                    .id(request.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fechar") {
                                launchSheetRequest = nil
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 1. Botão Grande de Novo Lançamento

    private var launchHeroButton: some View {
        Button {
            openLaunchSheet(with: defaultTransactionType)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Novo Lançamento")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("Registrar gasto ou receita rapidamente")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.86))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color.blue,
                        Color(red: 0.25, green: 0.35, blue: 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(.rect(cornerRadius: 18))
            .shadow(color: Color.blue.opacity(0.28), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Card Grande "Meu dinheiro" + Botão ? Único

    private var myMoneyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.headline)
                        .foregroundStyle(Color.blue)
                    Text("Meu dinheiro")
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                }

                Spacer()

                if !hasDismissedHelpButton {
                    Button {
                        dismissHelpButtonAndShowSuggestion()
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.blue)
                            .frame(width: 34, height: 34)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ajuda sobre Meu dinheiro")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Saldo disponível")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(availableBalance.brlCurrencyFormatted)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(availableBalance >= 0 ? Color.primary : Color.red)
                    .contentTransition(.numericText())
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Receitas", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.green)
                    Text(allIncomeTotal.brlCurrencyFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Gastos", systemImage: "arrow.up.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.red)
                    Text(allExpenseTotal.brlCurrencyFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 22))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
    }

    // MARK: - 3. Gráfico Básico Gastos x Receita (Swift Charts)

    private var incomeVsExpenseChartCard: some View {
        let netPeriodBalance = scopedIncomeTotal - scopedExpenseTotal

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gastos x Receita")
                        .font(.headline.bold())
                    Text("Comparativo de valores atuais")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Período", selection: $chartScope) {
                    ForEach(ChartScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            Chart(chartPoints) { point in
                BarMark(
                    x: .value("Tipo", point.label),
                    y: .value("Valor", point.amount),
                    width: .fixed(58)
                )
                .foregroundStyle(point.color.gradient)
                .cornerRadius(10)
                .annotation(position: .top, alignment: .center, spacing: 6) {
                    Text(point.amount.brlCurrencyFormatted)
                        .font(.caption.bold())
                        .foregroundStyle(point.color)
                }
            }
            .chartYScale(domain: 0...chartMaxDomain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount.formatted(.currency(code: "BRL").precision(.fractionLength(0))))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .frame(height: 210)
            .padding(.top, 6)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chartScope == .total ? "Balanço Geral" : "Balanço de \(Date().formatted(.dateTime.month(.wide).locale(Locale(identifier: "pt_BR"))).capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(netPeriodBalance.brlCurrencyFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(netPeriodBalance >= 0 ? Color.green : Color.red)
                }

                Spacer()

                Text("\(scopedTransactions.count) lançamento(s)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 22))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
    }

    // MARK: - Helpers & Dados

    private func openLaunchSheet(with type: TransactionType) {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        didCreateTransactionInSheet = false
        launchSheetRequest = LaunchSheetRequest(initialType: type)
    }

    private func dismissHelpButtonAndShowSuggestion() {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        UserDefaults.standard.set(true, forKey: AuthViewModel.homeMoneyTipDismissedKey(for: userId))
        hasDismissedHelpButton = true
        showMoneyTipSuggestion = true
    }

    private func syncHelpFlagForCurrentUser() {
        hasDismissedHelpButton = UserDefaults.standard.bool(
            forKey: AuthViewModel.homeMoneyTipDismissedKey(for: userId)
        )
    }

    private func loadSummaryData() async {
        let cached = LocalDataManager.shared.fetchAllActiveCachedTransactions(userId: userId)
        if !cached.isEmpty || transactions.isEmpty {
            self.transactions = cached
        }

        guard !token.isEmpty else { return }

        isLoading = transactions.isEmpty
        defer { isLoading = false }

        await LocalDataManager.shared.syncPendingTransactions(token: token)

        do {
            let fetched = try await TransactionsAPIService.shared.listTransactions(
                token: token,
                status: .active,
                page: 1,
                limit: 200
            )
            self.transactions = fetched
            LocalDataManager.shared.cacheTransactions(fetched)
        } catch {
            AppLogger.shared.warning(
                "Falha ao atualizar resumo do Hub Início (mantendo cache local): \(error.localizedDescription)",
                category: .network
            )
        }
    }
}

/// Overlay em tela cheia com fundo em blur (.ultraThinMaterial) e composição Apple HIG
/// acionado pelo botão "?" de "Meu dinheiro", com atalhos diretos para RECEITA e GASTO.
private struct MoneyTipSpotlightOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var symbolBounceTrigger: Bool = false

    let onSelectType: (TransactionType) -> Void
    let onDismiss: () -> Void

    private var tipAttributedText: AttributedString {
        var prefix = AttributedString("Aqui fica o seu saldo disponível, adicione um lançamento de ")

        var incomeLink = AttributedString("RECEITA")
        incomeLink.link = URL(string: "cofrinho-hub://launch/income")
        incomeLink.foregroundColor = .green
        incomeLink.underlineStyle = .single
        incomeLink.font = .body.weight(.semibold)

        let middle = AttributedString(" e lançamentos de ")

        var expenseLink = AttributedString("GASTO")
        expenseLink.link = URL(string: "cofrinho-hub://launch/expense")
        expenseLink.foregroundColor = .red
        expenseLink.underlineStyle = .single
        expenseLink.font = .body.weight(.semibold)

        let suffix = AttributedString(" para visualizar a movimentação do seu dinheiro.")

        prefix.append(incomeLink)
        prefix.append(middle)
        prefix.append(expenseLink)
        prefix.append(suffix)
        return prefix
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay {
                    Color.black
                        .opacity(colorScheme == .dark ? 0.36 : 0.14)
                        .ignoresSafeArea()
                }
                .onTapGesture {
                    let haptic = UISelectionFeedbackGenerator()
                    haptic.selectionChanged()
                    onDismiss()
                }

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(colorScheme == .dark ? 0.22 : 0.12))
                            .frame(width: 52, height: 52)

                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.blue)
                            .symbolEffect(.bounce.up.byLayer, value: symbolBounceTrigger)
                    }

                    Spacer()

                    Button {
                        let haptic = UISelectionFeedbackGenerator()
                        haptic.selectionChanged()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fechar apresentação")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Meu dinheiro")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.blue)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text("Acompanhe seu saldo em tempo real")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(tipAttributedText)
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .tint(.primary)
                        .environment(\.openURL, OpenURLAction { url in
                            if url.absoluteString == "cofrinho-hub://launch/income" {
                                onSelectType(.income)
                                return .handled
                            }
                            if url.absoluteString == "cofrinho-hub://launch/expense" {
                                onSelectType(.expense)
                                return .handled
                            }
                            return .systemAction
                        })
                }

                VStack(spacing: 0) {
                    spotlightActionRow(
                        title: "Lançar uma Receita",
                        subtitle: "Salário, Pix recebido ou entrada extra",
                        icon: "arrow.down.left.circle.fill",
                        tint: .green
                    ) {
                        onSelectType(.income)
                    }

                    Divider()
                        .padding(.leading, 58)

                    spotlightActionRow(
                        title: "Lançar um Gasto",
                        subtitle: "Compras do dia, cartão ou contas",
                        icon: "arrow.up.right.circle.fill",
                        tint: .red
                    ) {
                        onSelectType(.expense)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground).opacity(colorScheme == .dark ? 0.72 : 0.85))
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )

                Button {
                    let haptic = UISelectionFeedbackGenerator()
                    haptic.selectionChanged()
                    onDismiss()
                } label: {
                    Text("Entendi")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.primary)
                        .foregroundStyle(Color(.systemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.65),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 32, y: 14)
            .padding(.horizontal, 20)
        }
        .onAppear {
            symbolBounceTrigger.toggle()
        }
    }

    private func spotlightActionRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView(viewModel: AuthViewModel())
}
