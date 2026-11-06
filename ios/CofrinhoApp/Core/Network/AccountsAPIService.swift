import Foundation

/// Cliente de rede para gerenciamento de contas, cartões e formas de pagamento.
public final class AccountsAPIService: @unchecked Sendable {
    public static let shared = AccountsAPIService()

    public let baseURL: URL = URL(string: "http://198.89.99.42:3333")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Lista todas as contas ativas do usuário
    public func listAccounts(token: String, includeHidden: Bool = false) async throws -> [AccountModel] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/accounts"), resolvingAgainstBaseURL: true)!
        if includeHidden {
            components.queryItems = [URLQueryItem(name: "include_hidden", value: "true")]
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        return try await performRequest(request)
    }

    /// Cria uma nova conta ou cartão com suporte a parcelas e datas de fechamento/vencimento
    public func createAccount(
        token: String,
        name: String,
        type: String = "credit_card",
        icon: String = "creditcard.fill",
        color: String = "#0A84FF",
        allowsInstallments: Bool = false,
        closingDay: Int? = nil,
        dueDay: Int? = nil
    ) async throws -> AccountModel {
        let endpoint = baseURL.appendingPathComponent("/v1/accounts")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        var payload: [String: Any] = [
            "name": name,
            "type": type,
            "icon": icon,
            "color": color,
            "allows_installments": allowsInstallments
        ]

        if allowsInstallments {
            if let closingDay { payload["closing_day"] = closingDay }
            if let dueDay { payload["due_day"] = dueDay }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await performRequest(request)
    }

    /// Atualiza uma conta existente
    public func updateAccount(
        token: String,
        id: Int,
        name: String? = nil,
        type: String? = nil,
        icon: String? = nil,
        color: String? = nil,
        allowsInstallments: Bool? = nil,
        closingDay: Int? = nil,
        dueDay: Int? = nil,
        status: String? = nil
    ) async throws -> AccountModel {
        let endpoint = baseURL.appendingPathComponent("/v1/accounts/\(id)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if let type { payload["type"] = type }
        if let icon { payload["icon"] = icon }
        if let color { payload["color"] = color }
        if let allowsInstallments { payload["allows_installments"] = allowsInstallments }
        if let closingDay { payload["closing_day"] = closingDay }
        if let dueDay { payload["due_day"] = dueDay }
        if let status { payload["status"] = status }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await performRequest(request)
    }

    /// Remove suavemente (soft delete) uma conta
    public func deleteAccount(token: String, id: Int) async throws {
        let endpoint = baseURL.appendingPathComponent("/v1/accounts/\(id)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "Falha ao excluir conta")
        }
    }

    // MARK: - Helper de Execução
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown(reason: "Resposta inválida do servidor")
            }

            if !(200...299).contains(httpResponse.statusCode) {
                let problem = try? JSONDecoder().decode(ProblemDetailsDTO.self, from: data)
                let msg = problem?.detail ?? problem?.title ?? "Falha na requisição de contas"
                throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: msg)
            }

            return try JSONDecoder().decode(T.self, from: data)
        } catch let err as any AppErrorProtocol {
            throw err
        } catch let urlErr as URLError {
            if urlErr.code == .cannotConnectToHost || urlErr.code == .networkConnectionLost || urlErr.code == .cannotFindHost {
                throw NetworkError.serverUnreachable(host: "VPS Cofrinho (198.89.99.42:3333)")
            } else if urlErr.code == .timedOut {
                throw NetworkError.timeout
            } else if urlErr.code == .notConnectedToInternet {
                throw NetworkError.noConnection
            } else {
                throw NetworkError.unknown(reason: urlErr.localizedDescription)
            }
        } catch {
            throw NetworkError.unknown(reason: error.localizedDescription)
        }
    }
}

