import SwiftUI

/// Visualização de Perfil e Preferências de Segurança do Usuário.
public struct ProfileView: View {
    @Bindable var viewModel: AuthViewModel
    @State private var showLogoutConfirmation = false
    @State private var showServerConfig = false

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

                // MARK: - Segurança e Biometria
                securitySection

                // MARK: - Conexão e Rede
                networkSection

                // MARK: - Ações de Sessão
                sessionActionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Meu Perfil")
            .handleAnyAppError($viewModel.activeError)
            .sheet(isPresented: $showServerConfig) {
                ServerConfigSheet()
            }
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
                    Text(viewModel.currentUser?.username ?? "Usuário Cofrinho")
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
        Section("Conexão & Nuvem") {
            Button {
                showServerConfig = true
            } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Servidor da API")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(AuthAPIService.shared.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "network")
                            .foregroundStyle(Color.orange)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.bold())
                        .foregroundStyle(.tertiary)
                }
            }
        }
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
}

#Preview {
    ProfileView(viewModel: AuthViewModel())
}

