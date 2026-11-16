import SwiftUI

public struct CreateCategorySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: NewExpenseViewModel
    let token: String

    @State private var name: String = ""
    @State private var selectedIcon: String = "tag.fill"
    @State private var selectedColorHex: String = "#FF9500"
    @State private var isSubmitting: Bool = false
    @State private var activeError: (any AppErrorProtocol)?
    @FocusState private var isNameFocused: Bool

    private let availableIcons = [
        "cart.fill", "fork.knife", "car.fill", "house.fill",
        "bag.fill", "heart.fill", "cross.case.fill", "airplane",
        "gamecontroller.fill", "graduationcap.fill", "fuelpump.fill",
        "film.fill", "gift.fill", "bolt.fill", "wifi", "tag.fill"
    ]

    private let availableColors = [
        "#FF9500", "#FF2D55", "#007AFF", "#34C759",
        "#AF52DE", "#5856D6", "#5AC8FA", "#FFCC00"
    ]

    public init(viewModel: NewExpenseViewModel, token: String) {
        self.viewModel = viewModel
        self.token = token
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Preview do Ícone e Cor
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color(hex: selectedColorHex))
                                .frame(width: 72, height: 72)
                                .shadow(color: Color(hex: selectedColorHex).opacity(0.4), radius: 8, y: 4)

                            Image(systemName: selectedIcon)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)

                    // Nome da Categoria
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nome da Categoria")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        TextField("Ex: Lanches, Academia, Assinaturas", text: $name)
                            .focused($isNameFocused)
                            .autocorrectionDisabled(true)
                            .submitLabel(.done)
                            .onSubmit {
                                isNameFocused = false
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(.rect(cornerRadius: 12))
                    }

                    // Seletor de Ícone SF Symbol
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ícone")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            ForEach(availableIcons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedIcon == icon ? Color(hex: selectedColorHex).opacity(0.2) : Color(.secondarySystemBackground))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(selectedIcon == icon ? Color(hex: selectedColorHex) : Color.clear, lineWidth: 2)
                                            )
                                            .frame(height: 52)

                                        Image(systemName: icon)
                                            .font(.system(size: 20))
                                            .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColorHex) : .primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Seletor de Cores
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cor")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(availableColors, id: \.self) { hex in
                                Button {
                                    selectedColorHex = hex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: hex))
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
                            await saveCategory()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Criar Categoria")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                        .frame(height: 50)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.5) : Color(hex: selectedColorHex))
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                    .padding(.top, 10)
                }
                .padding()
            }
            .navigationTitle("Nova Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") {
                        isNameFocused = false
                    }
                    .font(.headline.bold())
                    .foregroundStyle(Color.blue)
                }
            }
            .handleAnyAppError($activeError)
        }
    }

    private func saveCategory() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            activeError = ValidationError.emptyTitle
            return
        }

        isSubmitting = true
        activeError = nil

        do {
            let created = try await CategoriesAPIService.shared.createCategory(
                token: token,
                name: trimmed,
                icon: selectedIcon,
                color: selectedColorHex
            )
            viewModel.categories.append(created)
            viewModel.selectedCategory = created
            AppLogger.shared.info("Nova categoria criada: \(trimmed)", category: .business)
            dismiss()
        } catch let err as any AppErrorProtocol {
            activeError = err
            AppLogger.shared.error("Erro ao criar categoria: \(err.errorDescription ?? err.localizedDescription)", category: .network)
            isSubmitting = false
        } catch {
            let unk = NetworkError.unknown(reason: error.localizedDescription)
            activeError = unk
            AppLogger.shared.error("Erro inesperado ao criar categoria: \(error.localizedDescription)", category: .network)
            isSubmitting = false
        }
    }
}
