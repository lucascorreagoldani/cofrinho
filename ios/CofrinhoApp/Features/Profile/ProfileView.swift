import SwiftUI

/// Visualização de Perfil, Preferências de Autonomia do Usuário, Gestão CRUD de Categorias/Contas
/// e Telemetria da API Pública do Cofrinho.
public struct ProfileView: View {
    @Bindable var viewModel: AuthViewModel
    @State private var showLogoutConfirmation = false

    @State private var publicStatus: PublicStatusDTO?
    @State private var isCheckingPublicStatus = false

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                // MARK: - Cartão do Usuário
                userHeaderSection

                // MARK: - Dados da Conta
                accountInfoSection

                // MARK: - Autonomia & Personalização
                personalizationSection

                // MARK: - Segurança e Biometria
                securitySection

                // MARK: - Conexão & API Pública
                networkSection

                // MARK: - Ações de Sessão
                sessionActionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Meu Perfil")
            .task {
                await refreshPublicApiStatus()
            }
            .handleAnyAppError($viewModel.activeError)
            .confirmationDialog(
                "Deseja realmente sair da sua conta?",
                isPresented: $showLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sair da Conta", role: .destructive) {
                    Task {
                        await viewModel.logout()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    // MARK: - Seções

    private var userHeaderSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.pink, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 64, height: 64)

                    Text(initials)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(viewModel.currentUser?.username ?? "usuario")")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(viewModel.currentUser?.email ?? "email@cofrinho.app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Conta Conectada")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var accountInfoSection: some View {
        Section("Informações Cadastrais") {
            HStack {
                Label("ID do Usuário", systemImage: "number")
                    .foregroundStyle(.primary)
                Spacer()
                Text("#\(viewModel.currentUser?.id ?? 1)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())
            }

            if let date = viewModel.currentUser?.registrationDate {
                HStack {
                    Label("Membro desde", systemImage: "calendar")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }

            if let lastLogin = viewModel.currentUser?.lastLoginDate {
                HStack {
                    Label("Último Acesso", systemImage: "clock")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(lastLogin.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
    }

    private var personalizationSection: some View {
        let token = viewModel.token ?? ""

        return Section("Autonomia & Personalização") {
            Picker(
                selection: Binding(
                    get: { viewModel.currentPreferences?.defaultTransactionTypeEnum ?? .expense },
                    set: { newValue in
                        Task {
                            await viewModel.updateDefaultTransactionType(newValue)
                        }
                    }
                )
            ) {
                ForEach(TransactionType.allCases) { itemType in
                    Text(itemType.localizedName).tag(itemType)
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lançamento Padrão")
                            .font(.body)
                        Text("Define Gasto ou Receita ao abrir o app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Color.orange)
                }
            }

            NavigationLink {
                CategoriesProfileManagerView(token: token)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Minhas Categorias")
                            .font(.body)
                        Text("Criar, editar e remover categorias")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(Color.orange)
                }
            }

            NavigationLink {
                AccountsProfileManagerView(token: token)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Minhas Contas & Cartões")
                            .font(.body)
                        Text("Configurar fechamento, vencimento e visibilidade")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "creditcard.fill")
                        .foregroundStyle(Color.blue)
                }
            }
        }
    }

    private var securitySection: some View {
        Section("Segurança & Acesso") {
            // Toggle de Face ID / Touch ID
            if BiometryService.shared.isBiometryAvailable {
                Toggle(isOn: Binding(
                    get: { viewModel.currentPreferences?.verification ?? false },
                    set: { newValue in
                        Task {
                            await viewModel.toggleBiometryInSettings(enable: newValue)
                        }
                    }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BiometryService.shared.biometryName)
                                .font(.body)
                            Text("Exigir biometria ao abrir o app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: BiometryService.shared.biometryIconName)
                            .foregroundStyle(Color.blue)
                    }
                }
            }

            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Criptografia Local")
                            .font(.body)
                        Text("Dados protegidos com iOS Keychain e SwiftData")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Color.green)
                }
            }
        }
    }

    private var networkSection: some View {
        Section("API Pública & Infraestrutura") {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Servidor de Produção VPS")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("Host Ryzen Dedicado (198.89.99.42:3333)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "cloud.fill")
                        .foregroundStyle(publicStatus?.status == "online" ? Color.green : Color.orange)
                }
                Spacer()
                if isCheckingPublicStatus {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Verificar") {
                        Task { await refreshPublicApiStatus(manual: true) }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color.blue)
                }
            }

            if let status = publicStatus {
                HStack(spacing: 12) {
                    statusPill(
                        title: "API v\(status.version)",
                        isHealthy: status.status == "online"
                    )
                    statusPill(
                        title: "PostgreSQL",
                        isHealthy: status.services.postgres == "healthy"
                    )
                    statusPill(
                        title: "Redis",
                        isHealthy: status.services.redis == "healthy"
                    )
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func statusPill(title: String, isHealthy: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isHealthy ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var sessionActionsSection: some View {
        Section {
            Button(role: .destructive) {
                showLogoutConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Label("Encerrar Sessão", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.headline)
                    }
                    Spacer()
                }
            }
        }
    }

    private var initials: String {
        guard let name = viewModel.currentUser?.username, !name.isEmpty else { return "C" }
        return String(name.prefix(2)).uppercased()
    }

    private func refreshPublicApiStatus(manual: Bool = false) async {
        isCheckingPublicStatus = true
        defer { isCheckingPublicStatus = false }
        do {
            publicStatus = try await AuthAPIService.shared.fetchPublicStatus()
        } catch {
            let normalized = CofrinhoErrorMapper.normalize(error)
            AppLogger.shared.warning("Falha ao verificar status público: \(normalized.errorDescription ?? error.localizedDescription)", category: .network)
            if manual {
                viewModel.activeError = normalized
            }
        }
    }
}

// MARK: - Subtela CRUD de Categorias (Editar em Laranja, Excluir em Vermelho)

private struct CategoriesProfileManagerView: View {
    let token: String

    @State private var categories: [CategoryModel] = []
    @State private var isLoading = false
    @State private var editingCategory: CategoryModel?
    @State private var isCreatingNew = false
    @State private var activeError: (any AppErrorProtocol)?

    @State private var iconOptions = ["cart.fill", "fork.knife", "car.fill", "house.fill", "gamecontroller.fill", "heart.fill", "graduationcap.fill", "airplane", "gift.fill", "bag.fill", "bolt.fill", "tag.fill"]
    @State private var colorOptions = ["#FF9500", "#34C759", "#007AFF", "#AF52DE", "#FF3B30", "#5856D6"]

    var body: some View {
        List {
            if isLoading && categories.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Carregando categorias...")
                    Spacer()
                }
            } else {
                ForEach(categories) { cat in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(cat.swiftUIColor.opacity(0.16))
                                .frame(width: 36, height: 36)
                            Image(systemName: cat.icon)
                                .foregroundStyle(cat.swiftUIColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(cat.name)
                                .font(.body.weight(.medium))
                            if cat.isDefault {
                                Text("Padrão")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            editingCategory = cat
                        } label: {
                            Label("Editar", systemImage: "pencil")
                        }
                        .tint(Color.orange)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await deleteCategory(cat) }
                        } label: {
                            Label("Excluir", systemImage: "trash.fill")
                        }
                        .tint(Color.red)
                    }
                }
            }
        }
        .navigationTitle("Minhas Categorias")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingNew = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.blue)
                }
            }
        }
        .task {
            await loadData()
        }
        .sheet(isPresented: $isCreatingNew) {
            CategoryEditorSheetView(
                token: token,
                category: nil,
                iconOptions: iconOptions,
                colorOptions: colorOptions,
                onSaved: {
                    Task { await loadData() }
                }
            )
        }
        .sheet(item: $editingCategory) { cat in
            CategoryEditorSheetView(
                token: token,
                category: cat,
                iconOptions: iconOptions,
                colorOptions: colorOptions,
                onSaved: {
                    Task { await loadData() }
                }
            )
        }
        .handleAnyAppError($activeError)
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        async let enumsTask = try? AuthAPIService.shared.fetchPublicEnums()
        do {
            let loaded = try await CategoriesAPIService.shared.listCategories(token: token)
            self.categories = loaded
            LocalDataManager.shared.cacheCategories(loaded)
        } catch let err as any AppErrorProtocol {
            self.activeError = err
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }

        if let catalog = await enumsTask, let pers = catalog.personalization {
            if !pers.categoryIcons.isEmpty { iconOptions = pers.categoryIcons }
            if !pers.colors.isEmpty { colorOptions = pers.colors }
        }
    }

    private func deleteCategory(_ cat: CategoryModel) async {
        do {
            try await CategoriesAPIService.shared.deleteCategory(token: token, id: cat.id)
            categories.removeAll { $0.id == cat.id }
            LocalDataManager.shared.cacheCategories(categories)
            NewExpenseViewModel.invalidateRemoteSyncCache()
        } catch let err as any AppErrorProtocol {
            self.activeError = err
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }
}

private struct CategoryEditorSheetView: View {
    let token: String
    let category: CategoryModel?
    let iconOptions: [String]
    let colorOptions: [String]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var isSaving = false
    @State private var activeError: (any AppErrorProtocol)?

    init(
        token: String,
        category: CategoryModel?,
        iconOptions: [String],
        colorOptions: [String],
        onSaved: @escaping () -> Void
    ) {
        self.token = token
        self.category = category
        self.iconOptions = iconOptions
        self.colorOptions = colorOptions
        self.onSaved = onSaved
        self._name = State(initialValue: category?.name ?? "")
        self._selectedIcon = State(initialValue: category?.icon ?? iconOptions.first ?? "tag.fill")
        self._selectedColor = State(initialValue: category?.color ?? colorOptions.first ?? "#FF9500")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome da Categoria") {
                    TextField("Ex: Mercado, Lazer...", text: $name)
                        .autocorrectionDisabled(true)
                }

                Section("Ícone") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .frame(width: 44, height: 44)
                                    .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.2) : Color(.secondarySystemBackground))
                                    .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) : .primary)
                                    .clipShape(.rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Cor") {
                    HStack(spacing: 12) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Button {
                                selectedColor = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white, lineWidth: selectedColor == hex ? 3 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(category == nil ? "Nova Categoria" : "Editar Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        Task { await save() }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .handleAnyAppError($activeError)
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            if let existing = category {
                _ = try await CategoriesAPIService.shared.updateCategory(
                    token: token,
                    id: existing.id,
                    name: trimmed,
                    icon: selectedIcon,
                    color: selectedColor
                )
            } else {
                _ = try await CategoriesAPIService.shared.createCategory(
                    token: token,
                    name: trimmed,
                    icon: selectedIcon,
                    color: selectedColor
                )
            }
            NewExpenseViewModel.invalidateRemoteSyncCache()
            onSaved()
            dismiss()
        } catch let err as any AppErrorProtocol {
            self.activeError = err
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }
}

// MARK: - Subtela CRUD de Contas e Cartões (Editar em Laranja, Excluir em Vermelho)

private struct AccountsProfileManagerView: View {
    let token: String

    @State private var accounts: [AccountModel] = []
    @State private var isLoading = false
    @State private var editingAccount: AccountModel?
    @State private var isCreatingNew = false
    @State private var activeError: (any AppErrorProtocol)?

    var body: some View {
        List {
            if isLoading && accounts.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Carregando contas...")
                    Spacer()
                }
            } else {
                ForEach(accounts) { acc in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(acc.swiftUIColor.opacity(0.16))
                                .frame(width: 36, height: 36)
                            Image(systemName: acc.icon)
                                .foregroundStyle(acc.swiftUIColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(acc.name)
                                .font(.body.weight(.medium))
                            Text(acc.accountTypeEnum.localizedName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if acc.status == RecordStatus.hidden.rawValue {
                            Text("Oculta")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.14))
                                .clipShape(.rect(cornerRadius: 6))
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            editingAccount = acc
                        } label: {
                            Label("Editar", systemImage: "pencil")
                        }
                        .tint(Color.orange)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await deleteAccount(acc) }
                        } label: {
                            Label("Excluir", systemImage: "trash.fill")
                        }
                        .tint(Color.red)
                    }
                }
            }
        }
        .navigationTitle("Minhas Contas & Cartões")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingNew = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.blue)
                }
            }
        }
        .task {
            await loadData()
        }
        .sheet(isPresented: $isCreatingNew) {
            AccountEditorSheetView(
                token: token,
                account: nil,
                onSaved: {
                    Task { await loadData() }
                }
            )
        }
        .sheet(item: $editingAccount) { acc in
            AccountEditorSheetView(
                token: token,
                account: acc,
                onSaved: {
                    Task { await loadData() }
                }
            )
        }
        .handleAnyAppError($activeError)
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await AccountsAPIService.shared.listAccounts(token: token, includeHidden: true)
            self.accounts = loaded
            LocalDataManager.shared.cacheAccounts(loaded.filter { $0.status == RecordStatus.active.rawValue })
        } catch let err as any AppErrorProtocol {
            self.activeError = err
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }

    private func deleteAccount(_ acc: AccountModel) async {
        do {
            try await AccountsAPIService.shared.deleteAccount(token: token, id: acc.id)
            accounts.removeAll { $0.id == acc.id }
            LocalDataManager.shared.cacheAccounts(accounts.filter { $0.status == RecordStatus.active.rawValue })
            NewExpenseViewModel.invalidateRemoteSyncCache()
        } catch let err as any AppErrorProtocol {
            self.activeError = err
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }
}

private struct AccountEditorSheetView: View {
    let token: String
    let account: AccountModel?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedType: AccountType
    @State private var allowsInstallments: Bool
    @State private var closingDay: Int
    @State private var dueDay: Int
    @State private var isHidden: Bool
    @State private var selectedColor: String
    @State private var isSaving = false
    @State private var activeError: (any AppErrorProtocol)?

    private let colors = ["#007AFF", "#AF52DE", "#34C759", "#FF9500", "#FF3B30", "#5856D6"]

    init(token: String, account: AccountModel?, onSaved: @escaping () -> Void) {
        self.token = token
        self.account = account
        self.onSaved = onSaved
        self._name = State(initialValue: account?.name ?? "")
        self._selectedType = State(initialValue: account?.accountTypeEnum ?? .creditCard)
        self._allowsInstallments = State(initialValue: account?.allowsInstallments ?? true)
        self._closingDay = State(initialValue: account?.closingDay ?? 20)
        self._dueDay = State(initialValue: account?.dueDay ?? 27)
        self._isHidden = State(initialValue: account?.status == RecordStatus.hidden.rawValue)
        self._selectedColor = State(initialValue: account?.color ?? "#007AFF")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identificação") {
                    TextField("Nome da conta ou cartão", text: $name)
                        .autocorrectionDisabled(true)

                    Picker("Tipo", selection: $selectedType) {
                        ForEach(AccountType.allCases) { type in
                            Text(type.localizedName).tag(type)
                        }
                    }
                }

                Section("Parcelamento & Fatura") {
                    Toggle("Permite parcelamento", isOn: $allowsInstallments)

                    if allowsInstallments {
                        Picker("Dia de fechamento", selection: $closingDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text("Dia \(day)").tag(day)
                            }
                        }

                        Picker("Dia de vencimento", selection: $dueDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text("Dia \(day)").tag(day)
                            }
                        }
                    }
                }

                if account != nil {
                    Section("Visibilidade") {
                        Toggle("Ocultar conta", isOn: $isHidden)
                    }
                }

                Section("Cor") {
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.self) { hex in
                            Button {
                                selectedColor = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white, lineWidth: selectedColor == hex ? 3 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(account == nil ? "Nova Conta" : "Editar Conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        Task { await save() }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .handleAnyAppError($activeError)
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            if let existing = account {
                _ = try await AccountsAPIService.shared.updateAccount(
                    token: token,
                    id: existing.id,
                    name: trimmed,
                    type: selectedType.rawValue,
                    icon: selectedType.defaultIcon,
                    color: selectedColor,
                    allowsInstallments: allowsInstallments,
                    closingDay: allowsInstallments ? closingDay : nil,
                    dueDay: allowsInstallments ? dueDay : nil,
                    status: isHidden ? RecordStatus.hidden.rawValue : RecordStatus.active.rawValue
                )
            } else {
                _ = try await AccountsAPIService.shared.createAccount(
                    token: token,
                    name: trimmed,
                    type: selectedType.rawValue,
                    icon: selectedType.defaultIcon,
                    color: selectedColor,
                    allowsInstallments: allowsInstallments,
                    closingDay: allowsInstallments ? closingDay : nil,
                    dueDay: allowsInstallments ? dueDay : nil
                )
            }
            NewExpenseViewModel.invalidateRemoteSyncCache()
            onSaved()
            dismiss()
        } catch let err as any AppErrorProtocol {
            self.activeError = err
        } catch {
            self.activeError = NetworkError.unknown(reason: error.localizedDescription)
        }
    }
}

#Preview {
    ProfileView(viewModel: AuthViewModel())
}
