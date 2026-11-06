import SwiftUI

/// Tela e Componente principal para Cadastro de Novo Gasto no Cofrinho.
/// Desenvolvida estritamente segundo os mockups canônicos e padrões nativos iOS 17+.
public struct NewExpenseView: View {
    @State private var viewModel = NewExpenseViewModel()
    let token: String

    @FocusState private var isAmountFocused: Bool
    @FocusState private var isDescriptionFocused: Bool

    public init(token: String) {
        self.token = token
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Card Principal "Novo Gasto"
                VStack(alignment: .leading, spacing: 18) {
                    // Cabeçalho do Card
                    HStack(spacing: 8) {
                        Text("💸")
                            .font(.system(size: 22))

                        Text("Novo Gasto")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)

                        Spacer()
                    }

                    // LINHA 1: Descrição e Valor (R$)
                    HStack(alignment: .top, spacing: 14) {
                        // Campo Descrição
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Descrição")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextField("Ex: Supermercado, Aluguel, Netflix...", text: $viewModel.descriptionText)
                                .focused($isDescriptionFocused)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isDescriptionFocused ? Color.blue : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .frame(maxWidth: .infinity)

                        // Campo Valor (R$)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Valor (R$)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextField("R$ 0,00", text: $viewModel.amountInputString)
                                .focused($isAmountFocused)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isAmountFocused ? Color.blue : Color.clear, lineWidth: 1.5)
                                )
                                .onChange(of: viewModel.amountInputString) { _, newValue in
                                    viewModel.updateAmountFromDigits(newValue)
                                }
                        }
                        .frame(width: 130)
                    }

                    // Sugestões Rápidas de Gastos Frequentes (Chips horizontais)
                    if !viewModel.filteredSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.filteredSuggestions) { suggestion in
                                    Button {
                                        let haptic = UIImpactFeedbackGenerator(style: .light)
                                        haptic.impactOccurred()
                                        viewModel.applySuggestion(suggestion)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "sparkles")
                                                .font(.caption2)
                                            Text(suggestion.description)
                                                .font(.caption.weight(.medium))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundStyle(Color.blue)
                                        .cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // LINHA 2: Data, Categoria (+ nova) e Conta (+ nova)
                    HStack(alignment: .top, spacing: 10) {
                        // Coluna 1: Data
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Text("📅")
                                    .font(.caption2)
                                Text("Data")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            DatePicker(
                                "",
                                selection: $viewModel.selectedDate,
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                        .frame(maxWidth: .infinity)

                        // Coluna 2: Categoria (+ nova)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                HStack(spacing: 4) {
                                    Text("🏷️")
                                        .font(.caption2)
                                    Text("Categoria")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("+ nova") {
                                    viewModel.showCreateCategorySheet = true
                                }
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color(red: 0.31, green: 0.27, blue: 0.90))
                            }

                            Menu {
                                ForEach(viewModel.categories) { cat in
                                    Button {
                                        viewModel.selectedCategory = cat
                                    } label: {
                                        Label(cat.name, systemImage: cat.icon)
                                    }
                                }
                            } label: {
                                HStack {
                                    if let selectedCat = viewModel.selectedCategory {
                                        Image(systemName: selectedCat.icon)
                                            .font(.caption)
                                            .foregroundStyle(selectedCat.swiftUIColor)
                                        Text(selectedCat.name)
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
                                .frame(height: 38)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)

                        // Coluna 3: Conta (+ nova)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                HStack(spacing: 4) {
                                    Text("💳")
                                        .font(.caption2)
                                    Text("Conta")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("+ nova") {
                                    viewModel.showCreateAccountSheet = true
                                }
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color(red: 0.31, green: 0.27, blue: 0.90))
                            }

                            Menu {
                                ForEach(viewModel.accounts) { acc in
                                    Button {
                                        viewModel.selectedAccount = acc
                                        if !acc.allowsInstallments {
                                            viewModel.isInstallmentsEnabled = false
                                        }
                                    } label: {
                                        Label(acc.name, systemImage: acc.icon)
                                    }
                                }
                            } label: {
                                HStack {
                                    if let selectedAcc = viewModel.selectedAccount {
                                        Image(systemName: selectedAcc.icon)
                                            .font(.caption)
                                            .foregroundStyle(selectedAcc.swiftUIColor)
                                        Text(selectedAcc.name)
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
                                .frame(height: 38)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // LINHA 3: Seção de Parcelamento (Ativa dinamicamente se a conta permitir)
                    if let account = viewModel.selectedAccount, account.allowsInstallments {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $viewModel.isInstallmentsEnabled) {
                                HStack(spacing: 6) {
                                    Image(systemName: "creditcard.and.123")
                                        .foregroundStyle(Color.blue)
                                    Text("Parcelar este gasto no cartão")
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                            .tint(Color.blue)

                            if viewModel.isInstallmentsEnabled {
                                Divider()

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Quantidade de Parcelas")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)

                                        Picker("Parcelas", selection: $viewModel.installmentsCount) {
                                            ForEach(2...72, id: \.self) { count in
                                                Text("\(count)x").tag(count)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }

                                    Spacer()

                                    if !viewModel.installmentSummaryText.isEmpty {
                                        Text(viewModel.installmentSummaryText)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(Color.blue)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.12))
                                            .cornerRadius(8)
                                    }
                                }

                                if !viewModel.invoiceTimelineText.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "info.circle")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(viewModel.invoiceTimelineText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground).opacity(0.6))
                        .cornerRadius(12)
                    }

                    // LINHA 4: Botão de Ação "+ Adicionar Gasto"
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()

                        isAmountFocused = false
                        isDescriptionFocused = false

                        Task {
                            _ = await viewModel.saveTransaction(token: token)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Spacer()
                            if viewModel.isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Adicionar Gasto")
                                    .font(.headline.weight(.bold))
                            }
                            Spacer()
                        }
                        .frame(height: 50)
                        .background(Color(red: 0.31, green: 0.27, blue: 0.90))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        .shadow(color: Color(red: 0.31, green: 0.27, blue: 0.90).opacity(0.35), radius: 8, y: 4)
                    }
                    .disabled(viewModel.isSaving)
                    .padding(.top, 4)
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 4)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Novo Gasto")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadInitialData(token: token)
        }
        .sheet(isPresented: $viewModel.showCreateCategorySheet) {
            CreateCategorySheetView(viewModel: viewModel, token: token)
        }
        .sheet(isPresented: $viewModel.showCreateAccountSheet) {
            CreateAccountSheetView(viewModel: viewModel, token: token)
        }
        .alert("Sucesso", isPresented: $viewModel.showSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.successFeedback ?? "Gasto registrado com sucesso.")
        }
        .handleAnyAppError($viewModel.activeError)
    }
}

