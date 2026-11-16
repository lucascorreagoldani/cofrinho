import SwiftUI

/// Visão raiz que orquestra o fluxo de autenticação, proteção biométrica em segundo plano
/// e a navegação principal do Cofrinho.
struct ContentView: View {
    @State private var authViewModel = AuthViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if authViewModel.isAuthenticated {
                    MainTabView(viewModel: authViewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    LoginView(viewModel: authViewModel)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: authViewModel.isAuthenticated)

            if authViewModel.isAuthenticated && authViewModel.isLockedByBiometry {
                biometryLockOverlay
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            authViewModel.handleScenePhaseChange(newPhase)
        }
    }

    private var biometryLockOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.14))
                        .frame(width: 88, height: 88)

                    Image(systemName: BiometryService.shared.biometryIconName)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Color.blue)
                }

                VStack(spacing: 6) {
                    Text("Cofrinho Protegido")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text("Confirme seu \(BiometryService.shared.biometryName) para continuar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        await authViewModel.unlockAndRefreshSessionOnForeground()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: BiometryService.shared.biometryIconName)
                        Text("Desbloquear com \(BiometryService.shared.biometryName)")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .clipShape(.rect(cornerRadius: 14))
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.top, 6)
            }
            .padding(32)
        }
    }
}

#Preview {
    ContentView()
}
