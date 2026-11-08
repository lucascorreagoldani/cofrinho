import Foundation

/// Cliente de rede para gerenciamento de gastos, transações e parcelamento na API do Cofrinho.
public final class TransactionsAPIService: Sendable {
    public static let shared = TransactionsAPIService()

    private let client: APIClient

    public init(client: APIClient = .shared) {
        self.client = client
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
        var queryItems = [
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let month { queryItems.append(URLQueryItem(name: "month", value: "\(month)")) }
        if let year { queryItems.append(URLQueryItem(name: "year", value: "\(year)")) }
        if let categoryId { queryItems.append(URLQueryItem(name: "category_id", value: "\(categoryId)")) }
        if let accountId { queryItems.append(URLQueryItem(name: "account_id", value: "\(accountId)")) }

        let endpoint = try Endpoint(
            path: "/v1/transactions",
            method: .get,
            token: token,
            queryItems: queryItems
        )
        return try await client.request(endpoint)
    }

    /// Busca sugestões de autocompletar baseadas no histórico de gastos frequentes
    public func getSuggestions(token: String, query: String = "") async throws -> [SuggestionItemDTO] {
        var queryItems: [URLQueryItem]? = nil
        if !query.isEmpty {
            queryItems = [URLQueryItem(name: "q", value: query)]
        }

        let endpoint = try Endpoint(
            path: "/v1/transactions/suggestions",
            method: .get,
            token: token,
            queryItems: queryItems,
            timeoutInterval: 8
        )
        return try await client.request(endpoint)
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

        let endpoint = try Endpoint(
            path: "/v1/transactions",
            method: .post,
            token: token,
            jsonBody: payload,
            timeoutInterval: 12
        )
        return try await client.request(endpoint)
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
        var payload: [String: Any] = [:]
        if let description { payload["description"] = description }
        if let amount { payload["amount"] = amount }
        if let date { payload["date"] = date }
        if let hasTime { payload["has_time"] = hasTime }
        if let categoryId { payload["category_id"] = categoryId }
        if let accountId { payload["account_id"] = accountId }
        if let status { payload["status"] = status }

        let endpoint = try Endpoint(
            path: "/v1/transactions/\(id)",
            method: .put,
            token: token,
            jsonBody: payload
        )
        return try await client.request(endpoint)
    }

    /// Exclui um gasto (soft delete), com opção de excluir apenas esta parcela ou todas as futuras
    public func deleteTransaction(token: String, id: Int, cascade: String = "single") async throws {
        let endpoint = try Endpoint(
            path: "/v1/transactions/\(id)",
            method: .delete,
            token: token,
            queryItems: [URLQueryItem(name: "cascade", value: cascade)]
        )
        try await client.execute(endpoint)
    }

    /// Alterna visibilidade do gasto (ativo <-> ocultado)
    public func toggleVisibility(token: String, id: Int) async throws -> TransactionModel {
        let endpoint = try Endpoint(
            path: "/v1/transactions/\(id)/visibility",
            method: .patch,
            token: token
        )
        return try await client.request(endpoint)
    }
}
