import SwiftUI

/// Sheet avançada de filtros do Extrato do Cofrinho.
/// Permite filtrar por Conta específica, Categoria, Período e ativar a visualização de gastos ocultos.
public struct TransactionsFilterSheetView: View {
    @Binding var selectedAccountId: Int?
    @Binding var selectedCategoryId: Int?
    @Binding var filterStatus: String
    @Binding var selectedMonth: Int
    @Binding var selectedYear: Int

    let accounts: [AccountModel]
    let categories: [CategoryModel]
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var tempAccountId: Int?
    @State private var tempCategoryId: Int?
    @State private var tempStatus: String
    @State private var tempMonth: Int
    @State private var tempYear: Int

    public init(
        selectedAccountId: Binding<Int?>,
        selectedCategoryId: Binding<Int?>,
        filterStatus: Binding<String>,
        selectedMonth: Binding<Int>,
        selectedYear: Binding<Int>,
        accounts: [AccountModel],
        categories: [CategoryModel],
        onApply: @escaping () -> Void
    ) {
        self._selectedAccountId = selectedAccountId
        self._selectedCategoryId = selectedCategoryId
        self._filterStatus = filterStatus
        self._selectedMonth = selectedMonth
        self._selectedYear = selectedYear
        self.accounts = accounts
        self.categories = categories
        self.onApply = onApply

        self._tempAccountId = State(initialValue: selectedAccountId.wrappedValue)
        self._tempCategoryId = State(initialValue: selectedCategoryId.wrappedValue)
        self._tempStatus = State(initialValue: filterStatus.wrappedValue)
        self._tempMonth = State(initialValue: selectedMonth.wrappedValue)
        self._tempYear = State(initialValue: selectedYear.wrappedValue)
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Filtro de Conta
                Section {
                    Picker("Conta de Pagamento", selection: $tempAccountId) {
                        Text("Todas as Contas")
                            .tag(nil as Int?)

                        ForEach(accounts) { acc in
                            HStack(spacing: 8) {
                                Image(systemName: acc.icon)
                                    .foregroundStyle(acc.swiftUIColor)
                                Text(acc.name)
                            }
                            .tag(acc.id as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Label("Conta", systemImage: "creditcard.fill")
                } footer: {
                    if let accId = tempAccountId, let acc = accounts.first(where: { $0.id == accId }) {
                        Text("Exibindo apenas lançamentos da conta \(acc.name).")
                    } else {
                        Text("Exibindo lançamentos de todas as contas cadastradas.")
                    }
                }

                // MARK: - Filtro de Categoria
                Section {
                    Picker("Categoria", selection: $tempCategoryId) {
                        Text("Todas as Categorias")
                            .tag(nil as Int?)

                        ForEach(categories) { cat in
                            HStack(spacing: 8) {
                                Image(systemName: cat.icon)
                                    .foregroundStyle(cat.swiftUIColor)
                                Text(cat.name)
                            }
                            .tag(cat.id as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Label("Categoria", systemImage: "tag.fill")
                } footer: {
                    if let catId = tempCategoryId, let cat = categories.first(where: { $0.id == catId }) {
                        Text("Exibindo apenas gastos categorizados em \(cat.name).")
                    } else {
                        Text("Exibindo gastos de todas as categorias.")
                    }
                }

                // MARK: - Status e Gastos Ocultos
                Section {
                    Picker("Status dos Lançamentos", selection: $tempStatus) {
                        Text("Ativas").tag("active")
                        Text("Todas (com ocultas)").tag("all")
                        Text("Apenas Ocultas").tag("hidden")
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                } header: {
                    Label("Visibilidade & Ocultas", systemImage: "eye.fill")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if tempStatus == "active" {
                            Text("Exibindo apenas gastos ativos no extrato.")
                        } else if tempStatus == "all" {
                            Text("Exibindo gastos ativos e gastos que você ocultou. Arraste qualquer item oculto no extrato para desocultá-lo.")
                        } else {
                            Text("Exibindo exclusivamente os gastos que você ocultou. Você pode desocultar qualquer um arrastando para o lado.")
                        }
                    }
                }

                // MARK: - Período Selecionado
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mês e Ano")
                                .font(.subheadline)
                            Text(periodFormattedText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper("", value: $tempMonth, in: 1...12)
                            .labelsHidden()
                    }

                    HStack {
                        Text("Ano")
                        Spacer()
                        Picker("Ano", selection: $tempYear) {
                            ForEach((currentYear - 2)...(currentYear + 5), id: \.self) { y in
                                Text(String(y)).tag(y)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Label("Data / Período", systemImage: "calendar")
                }

                // MARK: - Ações de Limpeza
                Section {
                    Button(role: .destructive) {
                        clearFilters()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Redefinir Todos os Filtros", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Filtros do Extrato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        applyChanges()
                    }
                    .font(.headline)
                }
            }
        }
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var periodFormattedText: String {
        let monthName = Month(rawValue: tempMonth)?.localizedName() ?? ""
        return "\(monthName) de \(tempYear)"
    }

    private func clearFilters() {
        tempAccountId = nil
        tempCategoryId = nil
        tempStatus = "active"
        let now = Date()
        tempMonth = Calendar.current.component(.month, from: now)
        tempYear = Calendar.current.component(.year, from: now)
    }

    private func applyChanges() {
        selectedAccountId = tempAccountId
        selectedCategoryId = tempCategoryId
        filterStatus = tempStatus
        selectedMonth = tempMonth
        selectedYear = tempYear
        dismiss()
        onApply()
    }
}

