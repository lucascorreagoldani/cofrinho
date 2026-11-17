import SwiftUI

/// Sheet para seleção rápida e salto direto de Data Exata, Mês ou Ano no Extrato do Cofrinho.
/// Permite alternar entre o calendário gráfico completo (para escolher qualquer dia específico)
/// e o seletor direto de Mês/Ano (para visualizar o mês inteiro).
public struct MonthYearPickerSheetView: View {
    @Binding var selectedDay: Int?
    @Binding var selectedMonth: Int
    @Binding var selectedYear: Int
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var tempMonth: Int
    @State private var tempYear: Int
    @State private var isExactDateMode: Bool
    @State private var selectedDate: Date

    private let availableYears: [Int] = {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((currentYear - 3)...(currentYear + 10))
    }()

    public init(
        selectedDay: Binding<Int?>,
        selectedMonth: Binding<Int>,
        selectedYear: Binding<Int>,
        onApply: @escaping () -> Void
    ) {
        self._selectedDay = selectedDay
        self._selectedMonth = selectedMonth
        self._selectedYear = selectedYear
        self.onApply = onApply

        let initialMonth = selectedMonth.wrappedValue
        let initialYear = selectedYear.wrappedValue
        let initialDay = selectedDay.wrappedValue ?? Calendar.current.component(.day, from: Date())

        self._tempMonth = State(initialValue: initialMonth)
        self._tempYear = State(initialValue: initialYear)
        self._isExactDateMode = State(initialValue: selectedDay.wrappedValue != nil)
        self._selectedDate = State(initialValue: Self.buildDate(day: initialDay, month: initialMonth, year: initialYear))
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // MARK: - Atalhos Rápidos
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ATALHOS RÁPIDOS")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                shortcutChip(title: "Hoje (Data Exata)", icon: "calendar.badge.clock", isPrimary: true) {
                                    let now = Date()
                                    let cal = Calendar.current
                                    isExactDateMode = true
                                    selectedDate = now
                                    tempMonth = cal.component(.month, from: now)
                                    tempYear = cal.component(.year, from: now)
                                }

                                shortcutChip(title: "Mês Atual Inteiro", icon: "calendar") {
                                    let now = Date()
                                    let cal = Calendar.current
                                    isExactDateMode = false
                                    tempMonth = cal.component(.month, from: now)
                                    tempYear = cal.component(.year, from: now)
                                    selectedDate = now
                                }

                                shortcutChip(title: "+1 Mês", icon: "arrow.right.circle") {
                                    addMonths(1)
                                }

                                shortcutChip(title: "+6 Meses", icon: "forward.circle") {
                                    addMonths(6)
                                }

                                shortcutChip(title: "+1 Ano", icon: "sparkles") {
                                    addMonths(12)
                                }

                                shortcutChip(title: "-1 Ano", icon: "backward.circle") {
                                    addMonths(-12)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // MARK: - Modo e Seletor de Período / Data Exata
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SELECIONE O PERÍODO")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        Picker("Modo de Seleção", selection: $isExactDateMode) {
                            Text("Data Exata").tag(true)
                            Text("Apenas Mês / Ano").tag(false)
                        }
                        .pickerStyle(.segmented)

                        if isExactDateMode {
                            DatePicker(
                                "Selecione a data",
                                selection: $selectedDate,
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "pt_BR"))
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(.rect(cornerRadius: 16))
                            .onChange(of: selectedDate) { _, newDate in
                                let cal = Calendar.current
                                tempMonth = cal.component(.month, from: newDate)
                                tempYear = cal.component(.year, from: newDate)
                            }
                        } else {
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
                                .onChange(of: tempMonth) { _, newMonth in
                                    syncSelectedDate(month: newMonth, year: tempYear)
                                }

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
                                .onChange(of: tempYear) { _, newYear in
                                    syncSelectedDate(month: tempMonth, year: newYear)
                                }
                            }
                            .frame(height: 150)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(.rect(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal)

                    // MARK: - Card de Pré-visualização
                    HStack(spacing: 12) {
                        Image(systemName: isExactDateMode ? "calendar" : "calendar.badge.clock")
                            .font(.title2)
                            .foregroundStyle(Color.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isExactDateMode ? "Data selecionada:" : "Visualizando extrato de:")
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
                    .clipShape(.rect(cornerRadius: 14))
                    .padding(.horizontal)

                    // MARK: - Botão de Confirmação
                    Button {
                        if isExactDateMode {
                            let cal = Calendar.current
                            selectedDay = cal.component(.day, from: selectedDate)
                            selectedMonth = cal.component(.month, from: selectedDate)
                            selectedYear = cal.component(.year, from: selectedDate)
                        } else {
                            selectedDay = nil
                            selectedMonth = tempMonth
                            selectedYear = tempYear
                        }
                        dismiss()
                        onApply()
                    } label: {
                        Text(isExactDateMode ? "Visualizar Esta Data" : "Visualizar Mês Inteiro")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .clipShape(.rect(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Selecionar Data ou Mês")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var previewTitle: String {
        if isExactDateMode {
            let cal = Calendar.current
            let day = cal.component(.day, from: selectedDate)
            let monthName = Month(date: selectedDate, calendar: cal).localizedName()
            let year = cal.component(.year, from: selectedDate)
            return "\(String(format: "%02d", day)) de \(monthName) de \(year)"
        }
        let monthName = Month(rawValue: tempMonth)?.localizedName() ?? ""
        return "\(monthName) de \(tempYear) (Mês Inteiro)"
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
            .clipShape(.rect(cornerRadius: 20))
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
        syncSelectedDate(month: month, year: year)
    }

    private func syncSelectedDate(month: Int, year: Int) {
        let day = Calendar.current.component(.day, from: selectedDate)
        selectedDate = Self.buildDate(day: day, month: month, year: year)
    }

    private static func buildDate(day: Int, month: Int, year: Int) -> Date {
        let cal = Calendar.current
        var baseComponents = DateComponents()
        baseComponents.year = year
        baseComponents.month = month
        baseComponents.day = 1
        let monthStart = cal.date(from: baseComponents) ?? Date()
        let maxDay = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        baseComponents.day = min(max(day, 1), maxDay)
        baseComponents.hour = 12
        return cal.date(from: baseComponents) ?? Date()
    }
}
