import SwiftUI

/// Sheet para seleção rápida e salto direto de Mês e Ano no Extrato do Cofrinho.
/// Permite navegar para meses distantes (ex: Novembro 2027) com atalhos e pickers nativos.
public struct MonthYearPickerSheetView: View {
    @Binding var selectedMonth: Int
    @Binding var selectedYear: Int
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var tempMonth: Int
    @State private var tempYear: Int

    private let months = [
        (1, "Janeiro"), (2, "Fevereiro"), (3, "Março"), (4, "Abril"),
        (5, "Maio"), (6, "Junho"), (7, "Julho"), (8, "Agosto"),
        (9, "Setembro"), (10, "Outubro"), (11, "Novembro"), (12, "Dezembro")
    ]

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
            VStack(spacing: 20) {
                // MARK: - Atalhos Rápidos
                VStack(alignment: .leading, spacing: 8) {
                    Text("ATALHOS RÁPIDOS")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            shortcutChip(title: "Mês Atual", icon: "calendar") {
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
                .padding(.top, 12)

                // MARK: - Seletor de Mês e Ano
                VStack(spacing: 12) {
                    Text("SELECIONE O PERÍODO")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    HStack(spacing: 16) {
                        // Picker de Mês
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mês")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Mês", selection: $tempMonth) {
                                ForEach(months, id: \.0) { item in
                                    Text(item.1).tag(item.0)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 140)
                            .clipped()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }

                        // Picker de Ano
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ano")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Ano", selection: $tempYear) {
                                ForEach(availableYears, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 140)
                            .clipped()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }

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
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(14)
                .padding(.horizontal)

                Spacer()

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
        .presentationDetents([.medium, .fraction(0.65)])
        .presentationDragIndicator(.visible)
    }

    private var previewTitle: String {
        var comp = DateComponents()
        comp.month = tempMonth
        comp.year = tempYear
        let date = Calendar.current.date(from: comp) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM 'de' yyyy"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: date).capitalized
    }

    private func shortcutChip(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.bold())
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .foregroundStyle(Color.primary)
            .cornerRadius(20)
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
