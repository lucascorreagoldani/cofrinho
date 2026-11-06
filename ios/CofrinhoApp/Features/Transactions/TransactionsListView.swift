import SwiftUI

/// Tela de Extrato Completo de Gastos e Transações do Usuário.
public struct TransactionsListView: View {
    let token: String

    @State private var transactions: [TransactionModel] = []
    @State private var isLoading: Bool = false
    @State private var showNewExpenseSheet: Bool = false
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false

    // Estado para exclusão em cascata
    @State private var transactionToDelete: TransactionModel?
    @State private var showDeleteConfirmation: Bool = false

    public init(token: String) {
        self.token = token
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Barra de Seleção de Mês/Ano
                monthSelectorHeader

                // MARK: - Card de Resumo Mensal
                monthlySummaryCard

                // MARK: - Lista de Gastos
                if isLoading && transactions.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Carregando gastos...")
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        prepareDelete(tx)
                                    } label: {
                                        Label("Excluir", systemImage: "trash.fill")
                                    }

                                    Button {
                                        Task {
                                            await toggleVisibility(tx)
                                        }
                                    } label: {
                                        Label(
                                            tx.status == "hidden" ? "Mostrar" : "Ocultar",
                                            systemImage: tx.status == "hidden" ? "eye.fill" : "eye.slash.fill"
                                        )
                                    }
                                    .tint(.secondary)
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await loadTransactions()
                    }
                }
            }
            .navigationTitle("Extrato")
            .toolbar {
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
            .sheet(isPresented: $showNewExpenseSheet) {
                NavigationStack {
                    NewExpenseView(token: token)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fechar") {
                                    showNewExpenseSheet = false
                                    Task {
                                        await loadTransactions()
                                    }
                                }
                            }
                        }
                }
            }
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
            .alert("Atenção", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Ocorreu um erro.")
            }
            .task {
                await loadTransactions()
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

            Text(monthYearTitle)
                .font(.headline)
                .foregroundStyle(.primary)

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

    private var monthlySummaryCard: some View {
        let total = transactions.reduce(Decimal(0)) { $0 + $1.amount }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.locale = Locale(identifier: "pt_BR")
        let totalStr = formatter.string(from: total as NSDecimalNumber) ?? "R$ 0,00"

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Gasto no Mês")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(totalStr)
                    .font(.title2.bold())
                    .foregroundStyle(Color.red)
            }
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(Color.red.opacity(0.8))
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
                .foregroundStyle(Color.red)
        }
        .padding(.vertical, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.gray.opacity(0.6))
            Text("Nenhum gasto neste mês")
                .font(.headline)
            Text("Toque no botão abaixo para adicionar seu primeiro gasto.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

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
        if month > 12 {
            month = 1
            year += 1
        } else if month < 1 {
            month = 12
            year -= 1
        }
        selectedMonth = month
        selectedYear = year
        Task {
            await loadTransactions()
        }
    }

    private func loadTransactions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            transactions = try await TransactionsAPIService.shared.listTransactions(
                token: token,
                month: selectedMonth,
                year: selectedYear
            )
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func prepareDelete(_ tx: TransactionModel) {
        transactionToDelete = tx
        if tx.isInstallment && (tx.totalInstallments ?? 1) > 1 {
            showDeleteConfirmation = true
        } else {
            Task {
                await performDelete(tx, cascade: "single")
            }
        }
    }

    private func performDelete(_ tx: TransactionModel, cascade: String) async {
        do {
            try await TransactionsAPIService.shared.deleteTransaction(
                token: token,
                id: tx.id,
                cascade: cascade
            )
            await loadTransactions()
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func toggleVisibility(_ tx: TransactionModel) async {
        do {
            _ = try await TransactionsAPIService.shared.toggleVisibility(token: token, id: tx.id)
            await loadTransactions()
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
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

