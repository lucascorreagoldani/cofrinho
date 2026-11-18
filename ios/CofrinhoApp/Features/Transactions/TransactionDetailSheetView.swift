import SwiftUI

/// Tela detalhada para inspeção, auditoria de modificações e edição completa de um lançamento no Cofrinho.
/// Permite editar todos os campos (descrição, valor, data, hora, categoria, conta, tipo, observações e status),
/// exibe quem e quando realizou a última modificação e concentra ocultar/excluir com segurança.
public struct TransactionDetailSheetView: View {
    private enum EditField: Int, CaseIterable, Hashable {
        case description = 0
        case amount = 1
        case notes = 2
    }

    @State private var transaction: TransactionModel
    let token: String
    let onUpdated: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var groupInstallments: [TransactionModel] = []
    @State private var isLoadingInstallments: Bool = false

    @State private var categories: [CategoryModel]
    @State private var accounts: [AccountModel]

    // MARK: - Edição Rápida de Observação
    @State private var isEditingNotes: Bool = false
    @State private var draftNotes: String = ""
    @State private var isSavingNotes: Bool = false
    @FocusState private var isNotesFocused: Bool

    // MARK: - Edição Completa do Lançamento
    @State private var isEditingFull: Bool = false
    @State private var isSavingFullEdit: Bool = false
    @State private var draftDescription: String = ""
    @State private var draftRawAmount: Double = 0.0
    @State private var draftAmountInput: String = ""
    @State private var draftDate: Date = Date()
    @State private var draftHasTime: Bool = false
    @State private var draftCategoryId: Int = 0
    @State private var draftAccountId: Int = 0
    @State private var draftType: TransactionType = .expense
    @State private var draftStatus: RecordStatus = .active
    @State private var draftFullNotes: String = ""
    @FocusState private var focusedEditField: EditField?

    // MARK: - Ações de Visibilidade e Exclusão
    @State private var isPerformingAction: Bool = false
    @State private var showVisibilityConfirmation: Bool = false
    @State private var showSingleDeleteConfirmation: Bool = false
    @State private var showInstallmentDeleteConfirmation: Bool = false

    @State private var activeError: (any AppErrorProtocol)?

    public init(
        transaction: TransactionModel,
        token: String,
        initialCategories: [CategoryModel] = [],
        initialAccounts: [AccountModel] = [],
        initiallyEditing: Bool = false,
        onUpdated: @escaping () -> Void = {}
    ) {
        self._transaction = State(initialValue: transaction)
        self.token = token
        self._categories = State(initialValue: initialCategories)
        self._accounts = State(initialValue: initialAccounts)
        self.onUpdated = onUpdated
        self._draftNotes = State(initialValue: transaction.notes ?? "")

        let amountDouble = NSDecimalNumber(decimal: transaction.amount).doubleValue
        self._isEditingFull = State(initialValue: initiallyEditing)
        self._draftDescription = State(initialValue: transaction.description)
        self._draftRawAmount = State(initialValue: amountDouble)
        self._draftAmountInput = State(initialValue: amountDouble.brlCurrencyFormatted)
        self._draftDate = State(initialValue: transaction.dateValue)
        self._draftHasTime = State(initialValue: transaction.hasTime)
        self._draftCategoryId = State(initialValue: transaction.categoryId)
        self._draftAccountId = State(initialValue: transaction.accountId)
        self._draftType = State(initialValue: transaction.typeEnum)
        self._draftStatus = State(initialValue: transaction.statusEnum == .hidden ? .hidden : .active)
        self._draftFullNotes = State(initialValue: transaction.notes ?? "")
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isEditingFull {
                        fullEditFormContent
                    } else {
                        heroHeaderCard
                        generalInfoCard
                        auditTrailCard
                        notesCard

                        if transaction.isInstallment {
                            installmentSummaryCard
                            installmentScheduleCard
                        }

                        actionsCard
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditingFull ? "Editar Lançamento" : "Detalhes do Lançamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditingFull {
                        Button("Cancelar") {
                            focusedEditField = nil
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditingFull = false
                            }
                        }
                        .disabled(isSavingFullEdit)
                    } else {
                        Button {
                            beginFullEditing()
                        } label: {
                            Label("Editar", systemImage: "pencil")
                        }
                        .foregroundStyle(Color.orange)
                        .disabled(isPerformingAction)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isEditingFull {
                        Button("Salvar") {
                            focusedEditField = nil
                            Task {
                                await saveFullUpdate()
                            }
                        }
                        .font(.headline.bold())
                        .disabled(isSavingFullEdit)
                    } else {
                        Button("Fechar") {
                            dismiss()
                        }
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    if isEditingFull {
                        Button {
                            moveEditFocus(by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .disabled(!canMoveEditFocus(by: -1))

                        Button {
                            moveEditFocus(by: 1)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 16, weight: .semibold))
                                if canMoveEditFocus(by: 1) {
                                    Text("Próximo")
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                        }
                        .disabled(!canMoveEditFocus(by: 1))

                        Spacer()

                        Button("OK") {
                            focusedEditField = nil
                        }
                        .font(.headline.bold())
                        .foregroundStyle(Color.blue)
                    } else if isNotesFocused {
                        Spacer()

                        Button("OK") {
                            isNotesFocused = false
                        }
                        .font(.headline.bold())
                        .foregroundStyle(Color.blue)
                    }
                }
            }
            .task {
                async let auxTask: Void = loadAuxiliaryListsIfNeeded()
                if transaction.isInstallment {
                    await loadInstallmentGroupDetails()
                }
                _ = await auxTask
            }
            .alert(
                transaction.statusEnum == .hidden ? "Desocultar este lançamento?" : "Ocultar este lançamento?",
                isPresented: $showVisibilityConfirmation
            ) {
                let isHidden = transaction.statusEnum == .hidden
                Button(isHidden ? "Desocultar" : "Ocultar", role: isHidden ? .none : .destructive) {
                    Task { await performToggleVisibility() }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                if transaction.statusEnum == .hidden {
                    Text("Deseja desocultar \"\(transaction.description)\"? Ele voltará a aparecer normalmente no extrato padrão.")
                } else {
                    Text("Deseja ocultar \"\(transaction.description)\"? Ele sairá do extrato padrão, mas continuará visível ao ativar o filtro de ocultos.")
                }
            }
            .alert(
                "Excluir este lançamento?",
                isPresented: $showSingleDeleteConfirmation
            ) {
                Button("Excluir Lançamento", role: .destructive) {
                    Task { await performDelete(cascade: .single) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Tem certeza de que deseja excluir \"\(transaction.description)\" no valor de \(transaction.formattedAmount)?")
            }
            .confirmationDialog(
                "Excluir Lançamento Parcelado",
                isPresented: $showInstallmentDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Excluir apenas esta parcela", role: .destructive) {
                    Task { await performDelete(cascade: .single) }
                }
                Button("Excluir esta e todas as futuras", role: .destructive) {
                    Task { await performDelete(cascade: .allFuture) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Este lançamento faz parte de um parcelamento. Deseja remover apenas esta parcela ou também todas as futuras?")
            }
            .handleAnyAppError($activeError)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Cards de Visualização

    private var heroHeaderCard: some View {
        let catColor = Color(hex: transaction.category?.color ?? "#FF9500")
        let isHidden = transaction.statusEnum == .hidden
        let isIncome = transaction.typeEnum == .income

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
                    .foregroundStyle(isHidden ? Color.secondary : (isIncome ? Color.green : Color.red))

                HStack(spacing: 8) {
                    Text(transaction.formattedDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if transaction.isModified {
                        Label("Modificado", systemImage: "pencil")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.14))
                            .clipShape(.rect(cornerRadius: 6))
                    }

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
                icon: transaction.typeEnum == .income ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                iconColor: transaction.typeEnum == .income ? .green : .red,
                label: "Tipo",
                value: transaction.typeEnum.localizedName
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

            Divider()

            detailRow(
                icon: transaction.isModified ? "pencil.circle.fill" : "doc.plaintext",
                iconColor: transaction.isModified ? .orange : .secondary,
                label: "Histórico",
                value: transaction.isModified ? "Modificado após criação" : "Registro original"
            )
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    private var auditTrailCard: some View {
        let fallbackUser = cachedProfileUser()
        let creatorDisplay: String = {
            if let creator = transaction.createdBy {
                return "@\(creator.username)"
            }
            if let creatorId = transaction.createdByUserId {
                if let fallback = fallbackUser, fallback.id == creatorId {
                    return "@\(fallback.username)"
                }
                return "@usuario_\(creatorId)"
            }
            if let fallback = fallbackUser, fallback.id == transaction.userId {
                return "@\(fallback.username)"
            }
            return "@usuario_\(transaction.userId)"
        }()

        let modifierDisplay: String = {
            if let user = transaction.updatedBy {
                return "@\(user.username)"
            }
            if let uid = transaction.updatedByUserId {
                if let fallback = fallbackUser, fallback.id == uid {
                    return "@\(fallback.username)"
                }
                return "@usuario_\(uid)"
            }
            if let fallback = fallbackUser {
                return "@\(fallback.username)"
            }
            return "Usuário autenticado"
        }()

        let modifiedDateText = transaction.formattedModifiedDateTime ?? "Registrada"

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("REGISTRO & AUDITORIA", systemImage: "clock.arrow.circlepath")
                    .font(.caption.bold())
                    .foregroundStyle(transaction.isModified ? Color.orange : Color.secondary)
                Spacer()
                if transaction.isModified {
                    Text("Modificado")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14))
                        .foregroundStyle(Color.orange)
                        .clipShape(.rect(cornerRadius: 6))
                } else {
                    Text("Original")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(Color.secondary)
                        .clipShape(.rect(cornerRadius: 6))
                }
            }

            detailRow(
                icon: "person.badge.plus",
                iconColor: .blue,
                label: "Adicionado por",
                value: creatorDisplay
            )

            Divider()

            detailRow(
                icon: "calendar.badge.plus",
                iconColor: .blue,
                label: "Criado em",
                value: transaction.formattedCreatedDateTime
            )

            if transaction.isModified {
                Divider()

                detailRow(
                    icon: "person.crop.circle.badge.checkmark",
                    iconColor: .orange,
                    label: "Modificado por",
                    value: modifierDisplay
                )

                Divider()

                detailRow(
                    icon: "calendar.badge.clock",
                    iconColor: .orange,
                    label: "Data da Modificação",
                    value: modifiedDateText
                )
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(transaction.isModified ? Color.orange.opacity(0.25) : Color.clear, lineWidth: 1)
        )
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
                    let hasNotes = !(transaction.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    Button(hasNotes ? "Editar" : "Adicionar") {
                        draftNotes = transaction.notes ?? ""
                        isEditingNotes = true
                    }
                    .font(.caption.bold())
                    .foregroundStyle(hasNotes ? Color.orange : Color.blue)
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

    private var actionsCard: some View {
        let isHidden = transaction.statusEnum == .hidden

        return VStack(spacing: 10) {
            Button {
                beginFullEditing()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                    Text("Editar Informações do Lançamento")
                        .font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.14))
                .foregroundStyle(Color.orange)
                .clipShape(.rect(cornerRadius: 12))
            }
            .disabled(isPerformingAction)

            HStack(spacing: 10) {
                Button {
                    showVisibilityConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isHidden ? "eye.fill" : "eye.slash.fill")
                        Text(isHidden ? "Desocultar" : "Ocultar")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(.rect(cornerRadius: 12))
                }
                .disabled(isPerformingAction)

                Button {
                    if transaction.isInstallment && (transaction.totalInstallments ?? 1) > 1 {
                        showInstallmentDeleteConfirmation = true
                    } else {
                        showSingleDeleteConfirmation = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                        Text("Excluir")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.14))
                    .foregroundStyle(Color.red)
                    .clipShape(.rect(cornerRadius: 12))
                }
                .disabled(isPerformingAction)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - Modo de Edição Completa

    private var fullEditFormContent: some View {
        let selectedCat = selectedDraftCategory
        let selectedAcc = selectedDraftAccount

        return VStack(alignment: .leading, spacing: 18) {
            if transaction.isInstallment {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.blue)
                    Text("A edição será aplicada a esta parcela e ficará registrada com data, hora e usuário modificador.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08))
                .clipShape(.rect(cornerRadius: 12))
            }

            // Descrição e Valor
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Descrição")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Descrição do lançamento", text: $draftDescription)
                        .focused($focusedEditField, equals: .description)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedEditField = .amount
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focusedEditField == .description ? Color.blue : Color.clear, lineWidth: 1.5)
                        )
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Valor (R$)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("R$ 0,00", text: $draftAmountInput)
                        .focused($focusedEditField, equals: .amount)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focusedEditField == .amount ? Color.blue : Color.clear, lineWidth: 1.5)
                        )
                        .onChange(of: draftAmountInput) { _, newValue in
                            updateDraftAmountFromDigits(newValue)
                        }
                }
                .frame(width: 132)
            }

            // Tipo (Gasto / Receita)
            VStack(alignment: .leading, spacing: 6) {
                Text("Tipo de Movimentação")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Tipo", selection: $draftType) {
                    ForEach(TransactionType.allCases) { itemType in
                        Text(itemType.localizedName).tag(itemType)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Categoria e Conta
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Categoria")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Menu {
                        ForEach(resolvedCategoryOptions) { cat in
                            Button {
                                draftCategoryId = cat.id
                            } label: {
                                Label(cat.name, systemImage: cat.icon)
                            }
                        }
                    } label: {
                        HStack {
                            if let cat = selectedCat {
                                Image(systemName: cat.icon)
                                    .font(.caption)
                                    .foregroundStyle(cat.swiftUIColor)
                                Text(cat.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            } else {
                                Text("Selecione...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Conta / Cartão")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Menu {
                        ForEach(resolvedAccountOptions) { acc in
                            Button {
                                draftAccountId = acc.id
                            } label: {
                                Label(acc.name, systemImage: acc.icon)
                            }
                        }
                    } label: {
                        HStack {
                            if let acc = selectedAcc {
                                Image(systemName: acc.icon)
                                    .font(.caption)
                                    .foregroundStyle(acc.swiftUIColor)
                                Text(acc.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            } else {
                                Text("Selecione...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Data e Horário
            VStack(spacing: 10) {
                HStack {
                    Label("Data do Lançamento", systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: $draftDate, displayedComponents: [.date])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 10))

                VStack(spacing: 8) {
                    Toggle("Incluir horário específico", isOn: $draftHasTime)
                        .font(.subheadline.weight(.medium))

                    if draftHasTime {
                        Divider()
                        HStack {
                            Label("Horário", systemImage: "clock")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            DatePicker("", selection: $draftDate, displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 10))
            }

            // Visibilidade no Extrato
            VStack(alignment: .leading, spacing: 6) {
                Text("Visibilidade no Extrato")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Status", selection: $draftStatus) {
                    Text("Ativo").tag(RecordStatus.active)
                    Text("Oculto").tag(RecordStatus.hidden)
                }
                .pickerStyle(.segmented)
            }

            // Observação Opcional
            VStack(alignment: .leading, spacing: 6) {
                Text("Observação (opcional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Ex: Comprado na promoção, dividir com...", text: $draftFullNotes)
                    .focused($focusedEditField, equals: .notes)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit {
                        focusedEditField = nil
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedEditField == .notes ? Color.blue : Color.clear, lineWidth: 1.5)
                    )
            }

            // Botão Salvar Alterações
            Button {
                focusedEditField = nil
                Task {
                    await saveFullUpdate()
                }
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    if isSavingFullEdit {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Salvar Alterações")
                            .font(.headline.bold())
                    }
                    Spacer()
                }
                .frame(height: 50)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 12))
            }
            .disabled(isSavingFullEdit)
            .padding(.top, 4)
        }
        .padding(18)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
    }

    // MARK: - Helpers de Edição & Dados

    private var resolvedCategoryOptions: [CategoryModel] {
        if !categories.isEmpty { return categories }
        if let cat = transaction.category {
            return [
                CategoryModel(
                    id: cat.id,
                    userId: transaction.userId,
                    name: cat.name,
                    icon: cat.icon,
                    color: cat.color
                )
            ]
        }
        return []
    }

    private var resolvedAccountOptions: [AccountModel] {
        if !accounts.isEmpty { return accounts }
        if let acc = transaction.account {
            return [
                AccountModel(
                    id: acc.id,
                    userId: transaction.userId,
                    name: acc.name,
                    type: acc.type,
                    icon: acc.icon,
                    color: acc.color
                )
            ]
        }
        return []
    }

    private var selectedDraftCategory: CategoryModel? {
        resolvedCategoryOptions.first(where: { $0.id == draftCategoryId })
    }

    private var selectedDraftAccount: AccountModel? {
        resolvedAccountOptions.first(where: { $0.id == draftAccountId })
    }

    private func beginFullEditing() {
        isEditingNotes = false
        draftDescription = transaction.description
        let amountDouble = NSDecimalNumber(decimal: transaction.amount).doubleValue
        draftRawAmount = amountDouble
        draftAmountInput = amountDouble.brlCurrencyFormatted
        draftDate = transaction.dateValue
        draftHasTime = transaction.hasTime
        draftCategoryId = transaction.categoryId
        draftAccountId = transaction.accountId
        draftType = transaction.typeEnum
        draftStatus = transaction.statusEnum == .hidden ? .hidden : .active
        draftFullNotes = transaction.notes ?? ""

        withAnimation(.easeInOut(duration: 0.2)) {
            isEditingFull = true
        }

        Task {
            await loadAuxiliaryListsIfNeeded()
        }
    }

    private func updateDraftAmountFromDigits(_ input: String) {
        let cleanDigits = input.filter { $0.isNumber }
        if let cents = Double(cleanDigits) {
            draftRawAmount = cents / 100.0
        } else {
            draftRawAmount = 0.0
        }
        let formatted = draftRawAmount.brlCurrencyFormatted
        guard draftAmountInput != formatted else { return }
        draftAmountInput = formatted
    }

    private func canMoveEditFocus(by offset: Int) -> Bool {
        guard let current = focusedEditField,
              let index = EditField.allCases.firstIndex(of: current) else { return false }
        let target = index + offset
        return EditField.allCases.indices.contains(target)
    }

    private func moveEditFocus(by offset: Int) {
        guard let current = focusedEditField,
              let index = EditField.allCases.firstIndex(of: current) else { return }
        let target = index + offset
        guard EditField.allCases.indices.contains(target) else { return }
        focusedEditField = EditField.allCases[target]
    }

    private func loadAuxiliaryListsIfNeeded() async {
        if categories.isEmpty {
            let cachedCats = LocalDataManager.shared.fetchCachedCategories()
            if !cachedCats.isEmpty { categories = cachedCats }
        }
        if accounts.isEmpty {
            let cachedAccs = LocalDataManager.shared.fetchCachedAccounts()
            if !cachedAccs.isEmpty { accounts = cachedAccs }
        }

        if categories.isEmpty {
            if let fetchedCats = try? await CategoriesAPIService.shared.listCategories(token: token) {
                categories = fetchedCats
                LocalDataManager.shared.cacheCategories(fetchedCats)
            }
        }
        if accounts.isEmpty {
            if let fetchedAccs = try? await AccountsAPIService.shared.listAccounts(token: token) {
                accounts = fetchedAccs
                LocalDataManager.shared.cacheAccounts(fetchedAccs)
            }
        }
    }

    private func cachedProfileUser() -> UserProfileDTO? {
        guard let json = KeychainHelper.shared.read(key: "cofrinho_cached_user_json"),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(UserProfileDTO.self, from: data)
    }

    private func saveFullUpdate() async {
        let trimmedDesc = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDesc.isEmpty else {
            activeError = ValidationError.emptyTitle
            return
        }
        guard draftRawAmount > 0 else {
            activeError = ValidationError.invalidAmount
            return
        }
        guard let category = selectedDraftCategory else {
            activeError = ValidationError.custom(message: "Selecione uma categoria válida.")
            return
        }
        guard let account = selectedDraftAccount else {
            activeError = ValidationError.custom(message: "Selecione uma conta ou cartão válido.")
            return
        }

        let resolvedDate: Date = {
            if draftHasTime {
                return draftDate
            }
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: draftDate) ?? draftDate
        }()

        let dateEpochMs = Int(resolvedDate.timeIntervalSince1970 * 1000)
        let trimmedNotes = draftFullNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes: String? = trimmedNotes.isEmpty ? nil : trimmedNotes
        let userProfile = cachedProfileUser()

        isSavingFullEdit = true
        defer { isSavingFullEdit = false }

        if transaction.id < 0 {
            LocalDataManager.shared.markOfflineUpdateTransaction(
                id: transaction.id,
                description: trimmedDesc,
                notes: normalizedNotes,
                amount: draftRawAmount,
                date: dateEpochMs,
                hasTime: draftHasTime,
                category: category,
                account: account,
                type: draftType.rawValue,
                status: draftStatus.rawValue,
                modifiedByUserId: userProfile?.id ?? transaction.userId,
                modifiedByUsername: userProfile?.username,
                modifiedByEmail: userProfile?.email
            )
            applyOfflineModelUpdate(
                description: trimmedDesc,
                notes: normalizedNotes,
                amount: draftRawAmount,
                dateMs: dateEpochMs,
                hasTime: draftHasTime,
                category: category,
                account: account,
                type: draftType.rawValue,
                status: draftStatus.rawValue,
                userProfile: userProfile
            )
            NewExpenseViewModel.invalidateRemoteSyncCache()
            isEditingFull = false
            onUpdated()
            return
        }

        do {
            let updated = try await TransactionsAPIService.shared.updateTransaction(
                token: token,
                id: transaction.id,
                description: trimmedDesc,
                notes: trimmedNotes,
                amount: draftRawAmount,
                date: dateEpochMs,
                hasTime: draftHasTime,
                categoryId: category.id,
                accountId: account.id,
                type: draftType.rawValue,
                status: draftStatus.rawValue
            )

            self.transaction = updated
            self.draftNotes = updated.notes ?? ""
            LocalDataManager.shared.cacheTransactions([updated])
            NewExpenseViewModel.invalidateRemoteSyncCache()

            if updated.isInstallment {
                await loadInstallmentGroupDetails()
            }

            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            isEditingFull = false
            onUpdated()
        } catch let netErr as NetworkError where isConnectionError(netErr) {
            LocalDataManager.shared.markOfflineUpdateTransaction(
                id: transaction.id,
                description: trimmedDesc,
                notes: normalizedNotes,
                amount: draftRawAmount,
                date: dateEpochMs,
                hasTime: draftHasTime,
                category: category,
                account: account,
                type: draftType.rawValue,
                status: draftStatus.rawValue,
                modifiedByUserId: userProfile?.id ?? transaction.userId,
                modifiedByUsername: userProfile?.username,
                modifiedByEmail: userProfile?.email
            )
            applyOfflineModelUpdate(
                description: trimmedDesc,
                notes: normalizedNotes,
                amount: draftRawAmount,
                dateMs: dateEpochMs,
                hasTime: draftHasTime,
                category: category,
                account: account,
                type: draftType.rawValue,
                status: draftStatus.rawValue,
                userProfile: userProfile
            )
            NewExpenseViewModel.invalidateRemoteSyncCache()
            isEditingFull = false
            onUpdated()
        } catch let appErr as any AppErrorProtocol {
            self.activeError = appErr
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }

    private func applyOfflineModelUpdate(
        description: String,
        notes: String?,
        amount: Double,
        dateMs: Int,
        hasTime: Bool,
        category: CategoryModel,
        account: AccountModel,
        type: String,
        status: String,
        userProfile: UserProfileDTO?
    ) {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        transaction.description = description
        transaction.notes = notes
        transaction.amount = Decimal(amount)
        transaction.date = dateMs
        transaction.hasTime = hasTime
        transaction.categoryId = category.id
        transaction.category = CategoryRelationDTO(
            id: category.id,
            name: category.name,
            icon: category.icon,
            color: category.color
        )
        transaction.accountId = account.id
        transaction.account = AccountRelationDTO(
            id: account.id,
            name: account.name,
            type: account.type,
            icon: account.icon,
            color: account.color
        )
        transaction.type = type
        transaction.status = status
        transaction.isModified = true
        transaction.modifiedAt = nowMs
        transaction.updatedAt = nowMs
        if let profile = userProfile {
            transaction.updatedByUserId = profile.id
            transaction.updatedBy = TransactionModifierUserDTO(
                id: profile.id,
                username: profile.username
            )
        }
        draftNotes = notes ?? ""
    }

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
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            LocalDataManager.shared.markOfflineUpdateNotes(id: transaction.id, notes: normalizedForModel)
            transaction.notes = normalizedForModel
            transaction.isModified = true
            transaction.modifiedAt = nowMs
            transaction.updatedAt = nowMs
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
            transaction = updated
            LocalDataManager.shared.cacheTransactions([updated])
            isEditingNotes = false
            onUpdated()
        } catch let netErr as NetworkError where isConnectionError(netErr) {
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            LocalDataManager.shared.markOfflineUpdateNotes(id: transaction.id, notes: normalizedForModel)
            transaction.notes = normalizedForModel
            transaction.isModified = true
            transaction.modifiedAt = nowMs
            transaction.updatedAt = nowMs
            isEditingNotes = false
            onUpdated()
        } catch let appErr as any AppErrorProtocol {
            self.activeError = appErr
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }

    private func performToggleVisibility() async {
        isPerformingAction = true
        defer { isPerformingAction = false }

        if transaction.id < 0 {
            LocalDataManager.shared.markOfflineToggleVisibility(id: transaction.id)
            transaction.status = transaction.statusEnum == .hidden ? RecordStatus.active.rawValue : RecordStatus.hidden.rawValue
            onUpdated()
            return
        }

        do {
            let updated = try await TransactionsAPIService.shared.toggleVisibility(token: token, id: transaction.id)
            transaction = updated
            LocalDataManager.shared.cacheTransactions([updated])
            onUpdated()
        } catch let err as NetworkError where isConnectionError(err) {
            LocalDataManager.shared.markOfflineToggleVisibility(id: transaction.id)
            transaction.status = transaction.statusEnum == .hidden ? RecordStatus.active.rawValue : RecordStatus.hidden.rawValue
            onUpdated()
        } catch let appErr as any AppErrorProtocol {
            self.activeError = appErr
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }

    private func performDelete(cascade: DeleteCascadeMode) async {
        isPerformingAction = true
        defer { isPerformingAction = false }

        if transaction.id < 0 {
            LocalDataManager.shared.markOfflineDelete(id: transaction.id, cascade: cascade)
            onUpdated()
            dismiss()
            return
        }

        do {
            try await TransactionsAPIService.shared.deleteTransaction(
                token: token,
                id: transaction.id,
                cascade: cascade
            )
            LocalDataManager.shared.removeSyncedTransaction(id: transaction.id, cascade: cascade)
            onUpdated()
            dismiss()
        } catch let err as NetworkError where isConnectionError(err) {
            LocalDataManager.shared.markOfflineDelete(id: transaction.id, cascade: cascade)
            onUpdated()
            dismiss()
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
