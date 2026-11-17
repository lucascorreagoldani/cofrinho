import SwiftUI

/// Tela e Componente principal para Cadastro de Novo Gasto no Cofrinho.
/// Desenvolvida estritamente segundo os mockups canônicos e padrões nativos iOS 17+.
public struct NewExpenseView: View {
    private enum FormField: Int, CaseIterable, Hashable {
        case description = 0
        case amount = 1
        case notes = 2
    }

    @State private var viewModel: NewExpenseViewModel
    let token: String
    private let onSaved: (() -> Void)?

    @FocusState private var focusedField: FormField?

    public init(token: String, initialDate: Date? = nil, onSaved: (() -> Void)? = nil) {
        self.token = token
        self.onSaved = onSaved
        self._viewModel = State(initialValue: NewExpenseViewModel(initialDate: initialDate))
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
                                .focused($focusedField, equals: .description)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.sentences)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .amount
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(.rect(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(focusedField == .description ? Color.blue : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .frame(maxWidth: .infinity)

                        // Campo Valor (R$)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Valor (R$)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextField("R$ 0,00", text: $viewModel.amountInputString)
                                .focused($focusedField, equals: .amount)
                                .keyboardType(.numberPad)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .multilineTextAlignment(.trailing)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(.rect(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(focusedField == .amount ? Color.blue : Color.clear, lineWidth: 1.5)
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
                                        .clipShape(.rect(cornerRadius: 16))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // LINHA 2: Categoria (+ nova) e Conta (+ nova) em duas colunas espaçosas
                    HStack(alignment: .top, spacing: 12) {
                        // Coluna 1: Categoria (+ nova)
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
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(.rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)

                        // Coluna 2: Conta (+ nova)
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
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(.rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }

                    // LINHA 3: Data do Gasto com DatePicker em tamanho intrínseco (evita restrições negativas de layout)
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Text("📅")
                                .font(.subheadline)
                            Text("Data do Gasto")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        DatePicker(
                            "",
                            selection: $viewModel.selectedDate,
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 10))

                    // LINHA 3.5: Observação Opcional do Lançamento
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("📝")
                                .font(.caption2)
                            Text("Observação (opcional)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        TextField("Ex: Comprado na promoção, dividir com...", text: $viewModel.notesText)
                            .focused($focusedField, equals: .notes)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit {
                                focusedField = nil
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(.rect(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(focusedField == .notes ? Color.blue : Color.clear, lineWidth: 1.5)
                            )
                    }

                    // LINHA 4: Seção de Parcelamento (Ativa dinamicamente se a conta permitir)
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
                                            .clipShape(.rect(cornerRadius: 8))
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
                        .clipShape(.rect(cornerRadius: 12))
                    }

                    // LINHA 4: Botão de Ação "+ Adicionar Gasto"
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()

                        focusedField = nil

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
                        .clipShape(.rect(cornerRadius: 12))
                        .shadow(color: Color(red: 0.31, green: 0.27, blue: 0.90).opacity(0.35), radius: 8, y: 4)
                    }
                    .disabled(viewModel.isSaving)
                    .padding(.top, 4)
                }
                .padding(20)
                .background(Color(.systemBackground))
                .clipShape(.rect(cornerRadius: 20))
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 4)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Novo Gasto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button {
                    moveFocus(by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(!canMoveFocus(by: -1))

                Button {
                    moveFocus(by: 1)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                        if canMoveFocus(by: 1) {
                            Text("Próximo")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
                .disabled(!canMoveFocus(by: 1))

                Spacer()

                Button("OK") {
                    focusedField = nil
                }
                .font(.headline.bold())
                .foregroundStyle(Color.blue)
            }
        }
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
            Button("OK", role: .cancel) {
                onSaved?()
            }
        } message: {
            Text(viewModel.successFeedback ?? "Gasto registrado com sucesso.")
        }
        .handleAnyAppError($viewModel.activeError)
    }

    private func canMoveFocus(by offset: Int) -> Bool {
        guard let current = focusedField,
              let index = FormField.allCases.firstIndex(of: current) else { return false }
        let target = index + offset
        return FormField.allCases.indices.contains(target)
    }

    private func moveFocus(by offset: Int) {
        guard let current = focusedField,
              let index = FormField.allCases.firstIndex(of: current) else { return }
        let target = index + offset
        guard FormField.allCases.indices.contains(target) else { return }
        focusedField = FormField.allCases[target]
    }
}

