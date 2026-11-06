import SwiftUI

/// Visão raiz que orquestra o fluxo de autenticação e a navegação principal do Cofrinho.
struct ContentView: View {
    @State private var authViewModel = AuthViewModel()

    var body: some View {
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
    }
}

#Preview {
    ContentView()
}
