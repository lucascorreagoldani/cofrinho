import SwiftUI

/// Tela detalhada e expansível para inspeção de um lançamento financeiro no Cofrinho.
/// Exibe dados completos, observações opcionais editáveis e, no caso de parcelamentos,
/// o valor total da compra e o cronograma mensal de todas as parcelas do grupo.
public struct TransactionDetailSheetView: View {
    @State private var transaction: TransactionModel
    let token: String
    let onUpdated: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var groupInstallments: [TransactionModel] = []
    @State private var isLoadingInstallments: Bool = false

    @State private var isEditingNotes: Bool = false
    @State private var draftNotes: String = ""
    @State private var isSavingNotes: Bool = false
    @State private var activeError: (any AppErrorProtocol)?
    @FocusState private var isNotesFocused: Bool

    public init(
        transaction: TransactionModel,
        token: String,
        onUpdated: @escaping () -> Void = {}
    ) {
        self._transaction = State(initialValue: transaction)
        self.token = token
        self.onUpdated = onUpdated
        self._draftNotes = State(initialValue: transaction.notes ?? "")
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroHeaderCard
                    generalInfoCard
                    notesCard

                    if transaction.isInstallment {
                        installmentSummaryCard
                        installmentScheduleCard
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Detalhes do Gasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") {
                        isNotesFocused = false
                    }
                    .font(.headline.bold())
                    .foregroundStyle(Color.blue)
                }
            }
            .task {
                if transaction.isInstallment {
                    await loadInstallmentGroupDetails()
                }
            }
            .handleAnyAppError($activeError)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Cards de Detalhes

    private var heroHeaderCard: some View {
        let catColor = Color(hex: transaction.category?.color ?? "#FF9500")
        let isHidden = transaction.statusEnum == .hidden

        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(catColor.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: transaction.category?.icon ?? "tag.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(catColor)
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(transaction.description)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(isHidden ? .secondary : .primary)

                    if let badge = transaction.installmentBadge {
                        Text(badge)
                            .font(.caption.bold())
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(.rect(cornerRadius: 6))
                    }
                }

                Text(transaction.formattedAmount)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(isHidden ? Color.secondary : Color.red)

                HStack(spacing: 8) {
                    Text(transaction.formattedDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if isHidden {
                        Label("Oculto", systemImage: "eye.slash.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.14))
                            .clipShape(.rect(cornerRadius: 6))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    private var generalInfoCard: some View {
        let accountTypeName: String = {
            if let rawType = transaction.account?.type,
               let enumType = AccountType(rawValue: rawType) {
                return enumType.localizedName
            }
            return "Conta"
        }()

        let fullDateTimeText: String = {
            if transaction.hasTime {
                return transaction.dateValue.formatted(
                    .dateTime
                        .day(.twoDigits)
                        .month(.wide)
                        .year()
                        .hour(.twoDigits(amPM: .omitted))
                        .minute(.twoDigits)
                        .locale(Locale(identifier: "pt_BR"))
                )
            }
            return transaction.dateValue.formatted(
                .dateTime
                    .day(.twoDigits)
                    .month(.wide)
                    .year()
                    .locale(Locale(identifier: "pt_BR"))
            )
        }()

        return VStack(alignment: .leading, spacing: 12) {
            Text("INFORMAÇÕES GERAIS")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            detailRow(
                icon: transaction.category?.icon ?? "tag.fill",
                iconColor: Color(hex: transaction.category?.color ?? "#FF9500"),
                label: "Categoria",
                value: transaction.category?.name ?? "Sem categoria"
            )

            Divider()

            detailRow(
                icon: transaction.account?.icon ?? "creditcard.fill",
                iconColor: Color(hex: transaction.account?.color ?? "#007AFF"),
                label: accountTypeName,
                value: transaction.account?.name ?? "Conta"
            )

            Divider()

            detailRow(
                icon: "calendar",
                iconColor: .blue,
                label: "Data",
                value: fullDateTimeText.capitalized
            )

            Divider()

            detailRow(
                icon: transaction.statusEnum == .hidden ? "eye.slash.fill" : "checkmark.circle.fill",
                iconColor: transaction.statusEnum == .hidden ? .secondary : .green,
                label: "Status",
                value: transaction.statusEnum == .hidden ? "Oculto no extrato padrão" : "Ativo no extrato"
            )
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Observações", systemImage: "note.text")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                if !isEditingNotes {
                    Button(transaction.notes == nil || transaction.notes?.isEmpty == true ? "Adicionar" : "Editar") {
                        draftNotes = transaction.notes ?? ""
                        isEditingNotes = true
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color.blue)
                }
            }

            if isEditingNotes {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Digite uma observação opcional sobre este lançamento...", text: $draftNotes)
                        .focused($isNotesFocused)
                        .autocorrectionDisabled(true)
                        .submitLabel(.done)
                        .onSubmit {
                            isNotesFocused = false
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 10))

                    HStack {
                        Button("Cancelar") {
                            isEditingNotes = false
                            draftNotes = transaction.notes ?? ""
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            Task {
                                await saveNotesUpdate()
                            }
                        } label: {
                            if isSavingNotes {
                                ProgressView()
                                    .scaleEffect(0.85)
                            } else {
                                Text("Salvar Observação")
                                    .font(.subheadline.bold())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: 10))
                        .disabled(isSavingNotes)
                    }
                }
            } else if let notes = transaction.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Nenhuma observação informada para este lançamento.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    private var installmentSummaryCard: some View {
        let totalCount = transaction.totalInstallments ?? max(groupInstallments.count, 1)
        let currentNumber = transaction.installmentNumber ?? 1
        let computedTotal: Decimal = {
            if groupInstallments.count == totalCount && !groupInstallments.isEmpty {
                return groupInstallments.reduce(Decimal(0)) { $0 + $1.amount }
            }
            return transaction.amount * Decimal(totalCount)
        }()
        let progress = Double(currentNumber) / Double(max(totalCount, 1))

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("RESUMO DO PARCELAMENTO", systemImage: "creditcard.and.123")
                    .font(.caption.bold())
                    .foregroundStyle(Color.blue)
                Spacer()
                Text("\(currentNumber)/\(totalCount)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(Color.blue)
                    .clipShape(.rect(cornerRadius: 6))
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Valor Total da Compra")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(computedTotal.brlCurrencyFormatted)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Valor desta Parcela")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(transaction.formattedAmount)
                        .font(.title3.bold())
                        .foregroundStyle(Color.blue)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(Color.blue)
                Text("Parcela \(currentNumber) de \(totalCount) parcelas no total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    private var installmentScheduleCard: some View {
        let itemsToRender: [InstallmentScheduleRow] = buildInstallmentScheduleRows()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("CRONOGRAMA DE COBRANÇA", systemImage: "calendar.badge.clock")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                if isLoadingInstallments {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }

            ForEach(itemsToRender) { row in
                HStack(spacing: 12) {
                    Text("\(row.number)/\(row.total)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(row.isSelected ? .white : Color.blue)
                        .frame(width: 44, height: 28)
                        .background(row.isSelected ? Color.blue : Color.blue.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.monthYearTitle)
                            .font(.subheadline.weight(row.isSelected ? .bold : .medium))
                            .foregroundStyle(.primary)

                        Text("Vencimento: \(row.dueDateFormatted)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(row.amountFormatted)
                            .font(.subheadline.bold())
                            .foregroundStyle(row.isSelected ? Color.blue : .primary)

                        Text(row.statusLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(row.statusColor)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(row.isSelected ? Color.blue.opacity(0.07) : Color.clear)
                .clipShape(.rect(cornerRadius: 10))

                if row.number < itemsToRender.count {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - Helpers de UI & Dados

    private func detailRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadInstallmentGroupDetails() async {
        guard let groupId = transaction.installmentGroupId else { return }

        let cached = LocalDataManager.shared.fetchCachedInstallmentGroup(groupId: groupId)
        if !cached.isEmpty {
            self.groupInstallments = cached
        }

        guard transaction.id > 0 else { return }

        isLoadingInstallments = true
        defer { isLoadingInstallments = false }

        do {
            let fetched = try await TransactionsAPIService.shared.getInstallmentGroup(
                token: token,
                groupId: groupId
            )
            self.groupInstallments = fetched
            LocalDataManager.shared.cacheTransactions(fetched)
        } catch {
            AppLogger.shared.warning(
                "Usando cache/projeção local para cronograma do parcelamento: \(error.localizedDescription)",
                category: .network
            )
        }
    }

    private func saveNotesUpdate() async {
        let trimmed = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedForModel: String? = trimmed.isEmpty ? nil : trimmed

        isSavingNotes = true
        defer { isSavingNotes = false }

        if transaction.id < 0 {
            LocalDataManager.shared.markOfflineUpdateNotes(id: transaction.id, notes: normalizedForModel)
            transaction.notes = normalizedForModel
            isEditingNotes = false
            onUpdated()
            return
        }

        do {
            let updated = try await TransactionsAPIService.shared.updateTransaction(
                token: token,
                id: transaction.id,
                notes: trimmed
            )
            transaction.notes = updated.notes
            LocalDataManager.shared.cacheTransactions([updated])
            isEditingNotes = false
            onUpdated()
        } catch let netErr as NetworkError where isConnectionError(netErr) {
            LocalDataManager.shared.markOfflineUpdateNotes(id: transaction.id, notes: normalizedForModel)
            transaction.notes = normalizedForModel
            isEditingNotes = false
            onUpdated()
        } catch let appErr as any AppErrorProtocol {
            self.activeError = appErr
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }

    private func isConnectionError(_ error: NetworkError) -> Bool {
        switch error {
        case .noConnection, .serverUnreachable, .timeout:
            return true
        default:
            return false
        }
    }

    private struct InstallmentScheduleRow: Identifiable {
        let id: Int
        let number: Int
        let total: Int
        let monthYearTitle: String
        let dueDateFormatted: String
        let amountFormatted: String
        let isSelected: Bool
        let statusLabel: String
        let statusColor: Color
    }

    private func buildInstallmentScheduleRows() -> [InstallmentScheduleRow] {
        let total = max(transaction.totalInstallments ?? groupInstallments.count, 1)
        let currentNumber = transaction.installmentNumber ?? 1
        let calendar = Calendar.current
        let nowComponents = calendar.dateComponents([.year, .month], from: Date())
        let nowYM = (nowComponents.year ?? 2026) * 100 + (nowComponents.month ?? 1)

        var byNumber: [Int: TransactionModel] = [:]
        for item in groupInstallments {
            if let num = item.installmentNumber {
                byNumber[num] = item
            }
        }

        return (1...total).map { num in
            let resolvedItem = byNumber[num]
            let estimatedDate: Date = {
                if let item = resolvedItem {
                    return item.dateValue
                }
                return calendar.date(byAdding: .month, value: num - currentNumber, to: transaction.dateValue) ?? transaction.dateValue
            }()

            let monthEnum = Month(date: estimatedDate, calendar: calendar)
            let yearValue = calendar.component(.year, from: estimatedDate)
            let monthValue = calendar.component(.month, from: estimatedDate)
            let itemYM = yearValue * 100 + monthValue
            let monthTitle = "\(monthEnum.localizedName()) de \(yearValue)"
            let amountValue = resolvedItem?.amount ?? transaction.amount
            let isSelected = (num == currentNumber)

            let (statusLabel, statusColor): (String, Color) = {
                if isSelected {
                    return ("Parcela atual", .blue)
                } else if itemYM < nowYM {
                    return ("Mês anterior", .secondary)
                } else if itemYM == nowYM {
                    return ("Este mês", .orange)
                } else {
                    return ("Futura", .secondary)
                }
            }()

            return InstallmentScheduleRow(
                id: num,
                number: num,
                total: total,
                monthYearTitle: monthTitle,
                dueDateFormatted: estimatedDate.brShortDateFormatted,
                amountFormatted: amountValue.brlCurrencyFormatted,
                isSelected: isSelected,
                statusLabel: statusLabel,
                statusColor: statusColor
            )
        }
    }
}
