import SwiftUI

/// Barra de navegação inferior (Tab Bar) principal do Cofrinho.
public struct MainTabView: View {
    @Bindable var viewModel: AuthViewModel
    @State private var selectedTab: TabItem = .home

    public enum TabItem: Hashable {
        case home
        case transactions
        case goals
        case profile
    }

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Aba Início (Cadastro Rápido de Novo Gasto)
            NavigationStack {
                NewExpenseView(token: viewModel.token ?? "")
            }
            .tabItem {
                Label("Novo Gasto", systemImage: "plus.circle.fill")
            }
            .tag(TabItem.home)

            // MARK: - Aba Extrato (Lista Completa de Gastos, Filtro e Parcelas)
            TransactionsListView(token: viewModel.token ?? "")
                .tabItem {
                    Label("Extrato", systemImage: "list.bullet.rectangle.portrait.fill")
                }
                .tag(TabItem.transactions)

            // MARK: - Aba Metas (Cofrinhos Inteligentes)
            NavigationStack {
                VStack(spacing: 16) {
                    Image(systemName: "target")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.green)
                    Text("Cofrinhos de Metas")
                        .font(.title2.bold())
                    Text("Em breve: Acompanhamento de metas financeiras.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .navigationTitle("Metas")
            }
            .tabItem {
                Label("Metas", systemImage: "target")
            }
            .tag(TabItem.goals)

            // MARK: - Aba Perfil
            ProfileView(viewModel: viewModel)
                .tabItem {
                    Label("Perfil", systemImage: "person.crop.circle.fill")
                }
                .tag(TabItem.profile)
        }
        .tint(Color.blue)
    }
}

#Preview {
    MainTabView(viewModel: AuthViewModel())
}
