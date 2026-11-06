import SwiftUI

/// Tela moderna de Login e Registro do Cofrinho.
public struct LoginView: View {
    @Bindable var viewModel: AuthViewModel

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case login
        case password
        case username
        case email
        case regPassword
        case confirmPassword
    }

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
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
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            // MARK: - Alerta Nativo de Erros
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
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.pink.opacity(0.3), radius: 12, x: 0, y: 6)

                Image(systemName: "banknote.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text("Cofrinho")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(viewModel.isRegistering ? "Crie sua conta segura" : "Seu copiloto de finanças pessoais")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var loginFormSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                // Campo Usuário ou Email
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    TextField("Usuário ou e-mail", text: $viewModel.loginInput)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .login)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 14))

                // Campo Senha
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    SecureField("Sua senha", text: $viewModel.passwordInput)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 14))
            }

            // Checkbox "Manter-se logado"
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
        .padding(.vertical, 8)
    }

    private var registrationFormSection: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                // Nome de Usuário
                HStack(spacing: 12) {
                    Image(systemName: "at")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    TextField("Nome de usuário (ex: lucas)", text: $viewModel.usernameInput)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 14))

                // E-mail
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    TextField("Seu melhor e-mail", text: $viewModel.emailInput)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 14))

                // Senha
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    SecureField("Senha (mínimo 8 caracteres)", text: $viewModel.registerPasswordInput)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .regPassword)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 14))

                // Confirmação de Senha
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    SecureField("Confirme a sua senha", text: $viewModel.confirmPasswordInput)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmPassword)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 14))
            }

            // Checkbox "Manter-se logado"
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
        .padding(.vertical, 8)
    }

    private var switchModeSection: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.isRegistering.toggle()
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
}

#Preview {
    LoginView(viewModel: AuthViewModel())
}

