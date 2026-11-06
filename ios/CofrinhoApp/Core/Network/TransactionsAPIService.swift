import Foundation

/// Cliente de rede para gerenciamento de gastos, transações e parcelamento na API do Cofrinho.
public final class TransactionsAPIService: @unchecked Sendable {
    public static let shared = TransactionsAPIService()

    public let baseURL: URL = URL(string: "http://198.89.99.42:3333")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Lista transações do usuário com filtros de mês/ano, categoria e status
    public func listTransactions(
        token: String,
        month: Int? = nil,
        year: Int? = nil,
        categoryId: Int? = nil,
        accountId: Int? = nil,
        status: String = "active",
        page: Int = 1,
        limit: Int = 50
    ) async throws -> [TransactionModel] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/transactions"), resolvingAgainstBaseURL: true)!
        var queryItems = [
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let month { queryItems.append(URLQueryItem(name: "month", value: "\(month)")) }
        if let year { queryItems.append(URLQueryItem(name: "year", value: "\(year)")) }
        if let categoryId { queryItems.append(URLQueryItem(name: "category_id", value: "\(categoryId)")) }
        if let accountId { queryItems.append(URLQueryItem(name: "account_id", value: "\(accountId)")) }

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        return try await performRequest(request)
    }

    /// Busca sugestões de autocompletar baseadas no histórico de gastos frequentes
    public func getSuggestions(token: String, query: String = "") async throws -> [SuggestionItemDTO] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/transactions/suggestions"), resolvingAgainstBaseURL: true)!
        if !query.isEmpty {
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8

        return try await performRequest(request)
    }

    /// Cadastra um novo gasto à vista ou parcelado
    public func createTransaction(
        token: String,
        description: String,
        amount: Double,
        date: Int,
        hasTime: Bool = false,
        categoryId: Int,
        accountId: Int,
        type: String = "expense",
        installmentsEnabled: Bool = false,
        installmentsCount: Int = 2
    ) async throws -> TransactionModel {
        let endpoint = baseURL.appendingPathComponent("/v1/transactions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12

        var payload: [String: Any] = [
            "description": description,
            "amount": amount,
            "date": date,
            "has_time": hasTime,
            "category_id": categoryId,
            "account_id": accountId,
            "type": type
        ]

        if installmentsEnabled && installmentsCount > 1 {
            payload["installments"] = [
                "enabled": true,
                "count": installmentsCount
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await performRequest(request)
    }

    /// Atualiza um gasto existente
    public func updateTransaction(
        token: String,
        id: Int,
        description: String? = nil,
        amount: Double? = nil,
        date: Int? = nil,
        hasTime: Bool? = nil,
        categoryId: Int? = nil,
        accountId: Int? = nil,
        status: String? = nil
    ) async throws -> TransactionModel {
        let endpoint = baseURL.appendingPathComponent("/v1/transactions/\(id)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        var payload: [String: Any] = [:]
        if let description { payload["description"] = description }
        if let amount { payload["amount"] = amount }
        if let date { payload["date"] = date }
        if let hasTime { payload["has_time"] = hasTime }
        if let categoryId { payload["category_id"] = categoryId }
        if let accountId { payload["account_id"] = accountId }
        if let status { payload["status"] = status }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await performRequest(request)
    }

    /// Exclui um gasto (soft delete), com opção de excluir apenas esta parcela ou todas as futuras
    public func deleteTransaction(token: String, id: Int, cascade: String = "single") async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/transactions/\(id)"), resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "cascade", value: cascade)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "Falha ao excluir gasto")
        }
    }

    /// Alterna visibilidade do gasto (ativo <-> ocultado)
    public func toggleVisibility(token: String, id: Int) async throws -> TransactionModel {
        let endpoint = baseURL.appendingPathComponent("/v1/transactions/\(id)/visibility")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        return try await performRequest(request)
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
                let msg = problem?.detail ?? problem?.title ?? "Falha na requisição de gastos"
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

