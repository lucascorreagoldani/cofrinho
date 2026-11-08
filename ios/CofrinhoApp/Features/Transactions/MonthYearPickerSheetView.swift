import SwiftUI

/// Sheet para seleção rápida e salto direto de Mês e Ano no Extrato do Cofrinho.
/// Permite navegar para meses distantes (ex: Novembro 2027) com atalhos e pickers nativos sem cortes visuais.
public struct MonthYearPickerSheetView: View {
    @Binding var selectedMonth: Int
    @Binding var selectedYear: Int
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var tempMonth: Int
    @State private var tempYear: Int

    private let availableYears: [Int] = {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((currentYear - 3)...(currentYear + 10))
    }()

    public init(
        selectedMonth: Binding<Int>,
        selectedYear: Binding<Int>,
        onApply: @escaping () -> Void
    ) {
        self._selectedMonth = selectedMonth
        self._selectedYear = selectedYear
        self.onApply = onApply
        self._tempMonth = State(initialValue: selectedMonth.wrappedValue)
        self._tempYear = State(initialValue: selectedYear.wrappedValue)
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // MARK: - Atalhos Rápidos
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ATALHOS RÁPIDOS")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                shortcutChip(title: "Hoje / Mês Atual", icon: "calendar.badge.clock", isPrimary: true) {
                                    let now = Date()
                                    tempMonth = Calendar.current.component(.month, from: now)
                                    tempYear = Calendar.current.component(.year, from: now)
                                }

                                shortcutChip(title: "+1 Mês", icon: "arrow.right.circle") {
                                    addMonths(1)
                                }

                                shortcutChip(title: "+6 Meses", icon: "forward.circle") {
                                    addMonths(6)
                                }

                                shortcutChip(title: "+1 Ano", icon: "sparkles") {
                                    tempYear += 1
                                }

                                shortcutChip(title: "-1 Ano", icon: "backward.circle") {
                                    tempYear -= 1
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // MARK: - Seletor de Mês e Ano Unificado e Espaçoso
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SELECIONE O PERÍODO")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        HStack(spacing: 0) {
                            // Picker de Mês fortemente tipado e internacionalizado via enum Month
                            Picker("Mês", selection: $tempMonth) {
                                ForEach(Month.allCases) { month in
                                    Text(month.localizedName())
                                        .tag(month.rawValue)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)

                            Divider()
                                .frame(height: 110)
                                .padding(.horizontal, 4)

                            // Picker de Ano
                            Picker("Ano", selection: $tempYear) {
                                ForEach(availableYears, id: \.self) { year in
                                    Text(String(year))
                                        .tag(year)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 120)
                        }
                        .frame(height: 150)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                    }
                    .padding(.horizontal)

                    // MARK: - Card de Pré-visualização
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title2)
                            .foregroundStyle(Color.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Visualizando extrato de:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(previewTitle)
                                .font(.headline.bold())
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                    .padding(.horizontal)

                    // MARK: - Botão de Confirmação
                    Button {
                        selectedMonth = tempMonth
                        selectedYear = tempYear
                        dismiss()
                        onApply()
                    } label: {
                        Text("Visualizar Este Mês")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Selecionar Mês")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
        }
        // Altura ampliada para caber todos os componentes sem cortes visuais
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.visible)
    }

    private var previewTitle: String {
        let monthName = Month(rawValue: tempMonth)?.localizedName() ?? ""
        return "\(monthName) de \(tempYear)"
    }

    private func shortcutChip(title: String, icon: String, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.bold())
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isPrimary ? Color.blue.opacity(0.12) : Color(.secondarySystemBackground))
            .foregroundStyle(isPrimary ? Color.blue : Color.primary)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isPrimary ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
    }

    private func addMonths(_ delta: Int) {
        var month = tempMonth + delta
        var year = tempYear
        while month > 12 {
            month -= 12
            year += 1
        }
        while month < 1 {
            month += 12
            year -= 1
        }
        tempMonth = month
        tempYear = year
    }
}
