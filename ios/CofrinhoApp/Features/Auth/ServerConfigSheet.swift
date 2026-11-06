import SwiftUI

/// Painel para seleção ou alteração do endereço da API do Cofrinho.
public struct ServerConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customURL: String = ""
    @State private var isTesting = false
    @State private var testResult: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Servidores Recomendados") {
                    ForEach(AuthAPIService.presetServers, id: \.url) { server in
                        Button {
                            AuthAPIService.shared.setBaseURLString(server.url)
                            customURL = server.url
                            testResult = nil
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(server.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(server.url)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if AuthAPIService.shared.baseURL.absoluteString == server.url {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.green)
                                }
                            }
                        }
                    }
                }

                Section("Endereço Customizado") {
                    HStack {
                        TextField("http://seu-ip:3333", text: $customURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        if !customURL.isEmpty {
                            Button("Salvar") {
                                AuthAPIService.shared.setBaseURLString(customURL)
                                testResult = nil
                            }
                            .bold()
                        }
                    }

                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                            } else {
                                Label("Testar Conexão", systemImage: "network")
                            }
                            Spacer()
                            if let testResult {
                                Text(testResult)
                                    .font(.caption.bold())
                                    .foregroundStyle(testResult.contains("OK") ? Color.green : Color.red)
                            }
                        }
                    }
                    .disabled(isTesting)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Conexão da API")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                customURL = AuthAPIService.shared.baseURL.absoluteString
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            let url = AuthAPIService.shared.baseURL.appendingPathComponent("/health")
            var request = URLRequest(url: url)
            request.timeoutInterval = 4

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    await MainActor.run {
                        self.testResult = "Conectado (200 OK)"
                        self.isTesting = false
                    }
                } else {
                    await MainActor.run {
                        self.testResult = "Resposta inválida"
                        self.isTesting = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.testResult = "Inacessível"
                    self.isTesting = false
                }
            }
        }
    }
}
