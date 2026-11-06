import SwiftUI

/// Tela moderna de Login e Registro do Cofrinho com navegação rápida de formulário (setas cima/baixo) e resposta instantânea de clique.
public struct LoginView: View {
    @Bindable var viewModel: AuthViewModel

    @FocusState private var focusedField: Field?
    @State private var showServerConfig = false
    @State private var showOfflineOptionAlert = false

    private enum Field: Int, CaseIterable, Hashable {
        case login = 0
        case password = 1
        case username = 2
        case email = 3
        case regPassword = 4
        case confirmPassword = 5
    }

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Cabeçalho & Logo
                    headerSection

                    // MARK: - Formulário Dinâmico (Login ou Registro)
                    if viewModel.isRegistering {
                        registrationFormSection
                    } else {
                        loginFormSection
                    }

                    // MARK: - Botão de Alternância (Login / Criar Conta)
                    switchModeSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // MARK: - Atalho para Ajustes de Servidor / Rede
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showServerConfig = true
                    } label: {
                        Image(systemName: "network")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }
                }

                // MARK: - Barra de Ferramentas do Teclado (Setas Cima / Baixo e Concluído)
                ToolbarItemGroup(placement: .keyboard) {
                    HStack(spacing: 18) {
                        Button {
                            moveToPreviousField()
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .disabled(!canMoveToPreviousField)

                        Button {
                            moveToNextField()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .disabled(!canMoveToNextField)
                    }

                    Spacer()

                    Button("OK") {
                        focusedField = nil
                    }
                    .font(.headline)
                    .foregroundStyle(Color.orange)
                }
            }
            // MARK: - Alerta Nativo de Erros
            .handleAnyAppError(Binding(
                get: { viewModel.activeError },
                set: { newErr in
                    viewModel.activeError = newErr
                    if let netErr = newErr as? NetworkError, case .serverUnreachable = netErr {
                        showOfflineOptionAlert = true
                    }
                }
            ))
            // MARK: - Modal de Alternância de Servidor
            .sheet(isPresented: $showServerConfig) {
                ServerConfigSheet()
            }
            // MARK: - Sugestão de Modo Offline se o Servidor Estiver Fora do Ar
            .alert("Servidor Inacessível", isPresented: $showOfflineOptionAlert) {
                Button("Entrar no Modo Offline") {
                    viewModel.loginOfflineMode()
                }
                Button("Configurar Servidor") {
                    showServerConfig = true
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Não foi possível conectar ao servidor da API. Deseja acessar o Cofrinho no Modo Offline para navegar pelo app?")
            }
            // MARK: - Diálogo de Habilitação do Face ID / Touch ID
            .alert(
                "Ativar \(BiometryService.shared.biometryName)?",
                isPresented: $viewModel.showBiometryPromptDialog
            ) {
                Button("Usar \(BiometryService.shared.biometryName)") {
                    Task {
                        await viewModel.confirmBiometryChoice(enable: true)
                    }
                }
                Button("Agora Não", role: .cancel) {
                    Task {
                        await viewModel.confirmBiometryChoice(enable: false)
                    }
                }
            } message: {
                Text("Deseja utilizar o \(BiometryService.shared.biometryName) para acessar suas finanças com rapidez e segurança nas próximas vezes?")
            }
        }
    }

    // MARK: - Componentes Visuais

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.pink.opacity(0.85), Color.orange.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.pink.opacity(0.3), radius: 10, x: 0, y: 5)

                Image(systemName: "banknote.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text("Cofrinho")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(viewModel.isRegistering ? "Crie sua conta segura" : "Seu copiloto de finanças pessoais")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var loginFormSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                // Campo 1: Usuário ou Email
                formFieldContainer(icon: "person.fill", field: .login) {
                    TextField("Usuário ou e-mail", text: $viewModel.loginInput)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .login)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .password
                        }
                }

                // Campo 2: Senha
                formFieldContainer(icon: "lock.fill", field: .password) {
                    SecureField("Sua senha", text: $viewModel.passwordInput)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            focusedField = nil
                            Task {
                                await viewModel.login()
                            }
                        }
                }
            }

            // Checkbox "Manter-se conectado"
            Toggle(isOn: $viewModel.keepLoggedIn) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.keepLoggedIn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.keepLoggedIn ? Color.green : Color.secondary)
                        .font(.system(size: 18))

                    Text("Manter-se conectado neste iPhone")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            // Botão Principal de Entrar
            Button {
                focusedField = nil
                Task {
                    await viewModel.login()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Entrar")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                            .font(.subheadline.bold())
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient(
                    colors: [Color.pink, Color.orange],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 16))
                .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var registrationFormSection: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                // Campo 1: Nome de Usuário
                formFieldContainer(icon: "at", field: .username) {
                    TextField("Nome de usuário (ex: lucas)", text: $viewModel.usernameInput)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .email
                        }
                }

                // Campo 2: E-mail
                formFieldContainer(icon: "envelope.fill", field: .email) {
                    TextField("Seu melhor e-mail", text: $viewModel.emailInput)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .regPassword
                        }
                }

                // Campo 3: Senha
                formFieldContainer(icon: "lock.fill", field: .regPassword) {
                    SecureField("Senha (mínimo 8 caracteres)", text: $viewModel.registerPasswordInput)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .regPassword)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .confirmPassword
                        }
                }

                // Campo 4: Confirmação de Senha
                formFieldContainer(icon: "lock.shield.fill", field: .confirmPassword) {
                    SecureField("Confirme a sua senha", text: $viewModel.confirmPasswordInput)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.go)
                        .onSubmit {
                            focusedField = nil
                            Task {
                                await viewModel.register()
                            }
                        }
                }
            }

            // Checkbox "Manter-se conectado"
            Toggle(isOn: $viewModel.keepLoggedIn) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.keepLoggedIn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.keepLoggedIn ? Color.green : Color.secondary)
                        .font(.system(size: 18))

                    Text("Manter-se conectado após o cadastro")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            // Botão Cadastrar
            Button {
                focusedField = nil
                Task {
                    await viewModel.register()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Criar Minha Conta")
                            .font(.headline)
                        Image(systemName: "sparkles")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient(
                    colors: [Color.green, Color.teal],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 16))
                .shadow(color: Color.teal.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var switchModeSection: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.isRegistering.toggle()
                focusedField = viewModel.isRegistering ? .username : .login
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.isRegistering ? "Já possui uma conta?" : "Ainda não tem conta?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(viewModel.isRegistering ? "Fazer Login" : "Registrar uma conta")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.orange)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers de Clique Instantâneo & Navegação de Teclado

    @ViewBuilder
    private func formFieldContainer<Content: View>(
        icon: String,
        field: Field,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(focusedField == field ? Color.orange : Color.secondary)
                .frame(width: 22)

            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(focusedField == field ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = field
        }
    }

    private var activeFieldList: [Field] {
        if viewModel.isRegistering {
            return [.username, .email, .regPassword, .confirmPassword]
        } else {
            return [.login, .password]
        }
    }

    private var canMoveToPreviousField: Bool {
        guard let current = focusedField,
              let index = activeFieldList.firstIndex(of: current) else { return false }
        return index > 0
    }

    private var canMoveToNextField: Bool {
        guard let current = focusedField,
              let index = activeFieldList.firstIndex(of: current) else { return false }
        return index < (activeFieldList.count - 1)
    }

    private func moveToPreviousField() {
        guard let current = focusedField,
              let index = activeFieldList.firstIndex(of: current),
              index > 0 else { return }
        focusedField = activeFieldList[index - 1]
    }

    private func moveToNextField() {
        guard let current = focusedField,
              let index = activeFieldList.firstIndex(of: current),
              index < (activeFieldList.count - 1) else { return }
        focusedField = activeFieldList[index + 1]
    }
}

#Preview {
    LoginView(viewModel: AuthViewModel())
}
