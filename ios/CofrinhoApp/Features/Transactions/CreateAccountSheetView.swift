import SwiftUI

public struct CreateAccountSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: NewExpenseViewModel
    let token: String

    @State private var name: String = ""
    @State private var selectedType: String = "credit_card"
    @State private var selectedColorHex: String = "#0A84FF"
    @State private var allowsInstallments: Bool = true
    @State private var closingDay: Int = 20
    @State private var dueDay: Int = 27
    @State private var isSubmitting: Bool = false
    @State private var activeError: (any AppErrorProtocol)?

    private let accountTypes = [
        ("credit_card", "Cartão de Crédito", "creditcard.fill"),
        ("pix", "PIX", "bolt.horizontal.fill"),
        ("bank_account", "Conta Corrente", "building.columns.fill"),
        ("cash", "Dinheiro", "banknote.fill")
    ]

    private let availableColors = [
        "#0A84FF", "#5E5CE6", "#FF9F0A", "#30D158",
        "#FF375F", "#64D2FF", "#BF5AF2", "#8E8E93"
    ]

    public init(viewModel: NewExpenseViewModel, token: String) {
        self.viewModel = viewModel
        self.token = token
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Nome da Conta
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nome da Conta ou Cartão")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        TextField("Ex: Nubank Mastercard, PIX C6 Bank, Dinheiro", text: $name)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                    }

                    // Tipo de Conta
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tipo")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("Tipo de Conta", selection: $selectedType) {
                            ForEach(accountTypes, id: \.0) { item in
                                Label(item.1, systemImage: item.2).tag(item.0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedType) { _, newType in
                            if newType == "credit_card" {
                                allowsInstallments = true
                            } else {
                                allowsInstallments = false
                            }
                        }
                    }

                    // Seção de Parcelamento e Faturas (Ativável para Cartão de Crédito)
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $allowsInstallments) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Aceita compras parceladas")
                                    .font(.subheadline.weight(.medium))
                                Text("Permite dividir gastos futuros em parcelas")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(Color.blue)

                        if allowsInstallments {
                            Divider()

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Fechamento")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Picker("Dia Fechamento", selection: $closingDay) {
                                        ForEach(1...31, id: \.self) { day in
                                            Text("Dia \(day)").tag(day)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(10)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Vencimento")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Picker("Dia Vencimento", selection: $dueDay) {
                                        ForEach(1...31, id: \.self) { day in
                                            Text("Dia \(day)").tag(day)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground).opacity(0.6))
                    .cornerRadius(12)

                    // Seletor de Cores
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cor de Identificação")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(availableColors, id: \.self) { hex in
                                Button {
                                    selectedColorHex = hex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(colorFromHex(hex))
                                            .frame(width: 36, height: 36)

                                        if selectedColorHex == hex {
                                            Circle()
                                                .strokeBorder(.white, lineWidth: 3)
                                                .frame(width: 36, height: 36)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Botão Salvar
                    Button {
                        Task {
                            await saveAccount()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Criar Conta")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                        .frame(height: 50)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.5) : colorFromHex(selectedColorHex))
                        .cornerRadius(12)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                    .padding(.top, 10)
                }
                .padding()
            }
            .navigationTitle("Nova Conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .handleAnyAppError($activeError)
        }
    }

    private func saveAccount() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            activeError = ValidationError.emptyTitle
            return
        }

        isSubmitting = true
        activeError = nil

        let iconName = accountTypes.first(where: { $0.0 == selectedType })?.2 ?? "creditcard.fill"

        do {
            let created = try await AccountsAPIService.shared.createAccount(
                token: token,
                name: trimmed,
                type: selectedType,
                icon: iconName,
                color: selectedColorHex,
                allowsInstallments: allowsInstallments,
                closingDay: allowsInstallments ? closingDay : nil,
                dueDay: allowsInstallments ? dueDay : nil
            )
            viewModel.accounts.append(created)
            viewModel.selectedAccount = created
            AppLogger.shared.info("Nova conta criada: \(trimmed)", category: .business)
            dismiss()
        } catch let err as any AppErrorProtocol {
            activeError = err
            AppLogger.shared.error("Erro ao criar conta: \(err.errorDescription ?? err.localizedDescription)", category: .network)
            isSubmitting = false
        } catch {
            let unk = NetworkError.unknown(reason: error.localizedDescription)
            activeError = unk
            AppLogger.shared.error("Erro inesperado ao criar conta: \(error.localizedDescription)", category: .network)
            isSubmitting = false
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (10, 132, 255)
        }
        return Color(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1.0)
    }
}

