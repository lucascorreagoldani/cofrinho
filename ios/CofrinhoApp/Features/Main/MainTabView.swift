import SwiftUI

/// Barra de navegação inferior (Tab Bar) principal do Cofrinho.
public struct MainTabView: View {
    @Bindable var viewModel: AuthViewModel
    @State private var selectedTab: TabItem = .profile

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
            // MARK: - Aba Início (Placeholder para o Dashboard)
            NavigationStack {
                VStack(spacing: 16) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.pink)
                    Text("Visão Geral")
                        .font(.title2.bold())
                    Text("Em breve: Dashboard com saldo e resumos rápidos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .navigationTitle("Início")
            }
            .tabItem {
                Label("Início", systemImage: "house.fill")
            }
            .tag(TabItem.home)

            // MARK: - Aba Extrato (Placeholder para Transações)
            NavigationStack {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.orange)
                    Text("Transações")
                        .font(.title2.bold())
                    Text("Em breve: Extrato completo de receitas e despesas.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .navigationTitle("Extrato")
            }
            .tabItem {
                Label("Extrato", systemImage: "list.bullet.rectangle.portrait.fill")
            }
            .tag(TabItem.transactions)

            // MARK: - Aba Metas (Placeholder para Cofrinhos)
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

            // MARK: - Aba Perfil (Implementada)
            ProfileView(viewModel: viewModel)
                .tabItem {
                    Label("Perfil", systemImage: "person.crop.circle.fill")
                }
                .tag(TabItem.profile)
        }
        .tint(Color.orange)
    }
}

#Preview {
    MainTabView(viewModel: AuthViewModel())
}

