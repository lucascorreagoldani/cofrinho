import SwiftUI

/// Tela moderna de Login e Registro do Cofrinho conectada exclusivamente à VPS de produção.
/// Desenvolvida para máxima velocidade de resposta ao toque (0 delay), navegação rápida de formulário
/// com setas cima/baixo e suporte nativo ao preenchimento automático do iOS Keychain.
public struct LoginView: View {
    @Bindable var viewModel: AuthViewModel

    @FocusState private var focusedField: Field?

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
                    // MARK: - Cabeçalho & Logo do App
                    headerSection
                        .padding(.top, 12)

                    // MARK: - Formulário de Entrada
                    VStack(spacing: 16) {
                        if viewModel.isRegistering {
                            registrationFields
                        } else {
                            loginFields
                        }

                        // Checkbox Manter-se conectado
                        Toggle(isOn: $viewModel.keepLoggedIn) {
                            HStack(spacing: 8) {
                                Image(systemName: viewModel.keepLoggedIn ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.keepLoggedIn ? Color.green : Color.secondary)
                                    .font(.system(size: 18))

                                Text(viewModel.isRegistering ? "Manter-se conectado após o cadastro" : "Manter-se conectado neste iPhone")
                                    .font(.footnote)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                        // Botão Principal de Ação
                        actionButton

                        // Alternar entre Login e Cadastro
                        switchModeSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.immediately)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // MARK: - Barra de Ferramentas de Formulário no Teclado
                ToolbarItem(placement: .keyboard) {
                    HStack {
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

                        Spacer()

                        Button("OK") {
                            focusedField = nil
                        }
                        .font(.headline)
                        .foregroundStyle(Color.orange)
                    }
                }
            }
            // MARK: - Tratamento Centralizado de Erros (RFC 9457 & AppError)
            .handleAnyAppError($viewModel.activeError)
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

    // MARK: - Seções Visuais

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.pink.opacity(0.85), Color.orange.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 82, height: 82)
                    .shadow(color: Color.pink.opacity(0.25), radius: 8, x: 0, y: 4)

                Image(systemName: "banknote.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text("Cofrinho")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(viewModel.isRegistering ? "Crie sua conta segura" : "Seu copiloto de finanças pessoais")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loginFields: some View {
        VStack(spacing: 12) {
            // Campo 1: Usuário ou E-mail
            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .foregroundStyle(focusedField == .login ? Color.orange : Color.secondary)
                    .frame(width: 22, alignment: .center)

                TextField("Usuário ou e-mail", text: $viewModel.loginInput)
                    .focused($focusedField, equals: .login)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .password
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focusedField == .login ? Color.orange.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )

            // Campo 2: Senha
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(focusedField == .password ? Color.orange : Color.secondary)
                    .frame(width: 22, alignment: .center)

                SecureField("Sua senha", text: $viewModel.passwordInput)
                    .focused($focusedField, equals: .password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit {
                        focusedField = nil
                        Task {
                            await viewModel.login()
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focusedField == .password ? Color.orange.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
        }
    }

    private var registrationFields: some View {
        VStack(spacing: 12) {
            // Campo 1: Nome de Usuário
            HStack(spacing: 12) {
                Image(systemName: "at")
                    .foregroundStyle(focusedField == .username ? Color.orange : Color.secondary)
                    .frame(width: 22, alignment: .center)

                TextField("Nome de usuário (ex: lucas)", text: $viewModel.usernameInput)
                    .focused($focusedField, equals: .username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .email
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focusedField == .username ? Color.orange.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )

            // Campo 2: E-mail (textContentType sem keyboardType conflitante para evitar bug de predição do iOS)
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(focusedField == .email ? Color.orange : Color.secondary)
                    .frame(width: 22, alignment: .center)

                TextField("Seu melhor e-mail", text: $viewModel.emailInput)
                    .focused($focusedField, equals: .email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .regPassword
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focusedField == .email ? Color.orange.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )

            // Campo 3: Senha
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(focusedField == .regPassword ? Color.orange : Color.secondary)
                    .frame(width: 22, alignment: .center)

                SecureField("Senha (mínimo 8 caracteres)", text: $viewModel.registerPasswordInput)
                    .focused($focusedField, equals: .regPassword)
                    .textContentType(.newPassword)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .confirmPassword
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focusedField == .regPassword ? Color.orange.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )

            // Campo 4: Confirmação de Senha
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(focusedField == .confirmPassword ? Color.orange : Color.secondary)
                    .frame(width: 22, alignment: .center)

                SecureField("Confirme a sua senha", text: $viewModel.confirmPasswordInput)
                    .focused($focusedField, equals: .confirmPassword)
                    .textContentType(.newPassword)
                    .submitLabel(.done)
                    .onSubmit {
                        focusedField = nil
                        Task {
                            await viewModel.register()
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(focusedField == .confirmPassword ? Color.orange.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )

            Text("A senha deve conter no mínimo 8 caracteres, uma letra maiúscula e um número.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private var actionButton: some View {
        Button {
            focusedField = nil
            Task {
                if viewModel.isRegistering {
                    await viewModel.register()
                } else {
                    await viewModel.login()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(viewModel.isRegistering ? "Criar Minha Conta" : "Entrar")
                        .font(.headline)
                    Image(systemName: viewModel.isRegistering ? "sparkles" : "arrow.right")
                        .font(.subheadline.bold())
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(LinearGradient(
                colors: viewModel.isRegistering ? [Color.green, Color.teal] : [Color.pink, Color.orange],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 14))
            .shadow(color: (viewModel.isRegistering ? Color.teal : Color.orange).opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .disabled(viewModel.isLoading)
        .padding(.top, 4)
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

    // MARK: - Navegação Rápida entre Campos

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
