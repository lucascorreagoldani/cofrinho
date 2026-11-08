import Foundation

/// Cliente de rede para gerenciamento de contas, cartões e formas de pagamento na API do Cofrinho.
public final class AccountsAPIService: Sendable {
    public static let shared = AccountsAPIService()

    private let client: APIClient

    public init(client: APIClient = .shared) {
        self.client = client
    }

    /// Lista todas as contas ativas do usuário
    public func listAccounts(token: String, includeHidden: Bool = false) async throws -> [AccountModel] {
        var queryItems: [URLQueryItem]? = nil
        if includeHidden {
            queryItems = [URLQueryItem(name: "include_hidden", value: "true")]
        }

        let endpoint = try Endpoint(
            path: "/v1/accounts",
            method: .get,
            token: token,
            queryItems: queryItems
        )
        return try await client.request(endpoint)
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

        let endpoint = try Endpoint(
            path: "/v1/accounts",
            method: .post,
            token: token,
            jsonBody: payload
        )
        return try await client.request(endpoint)
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
        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if let type { payload["type"] = type }
        if let icon { payload["icon"] = icon }
        if let color { payload["color"] = color }
        if let allowsInstallments { payload["allows_installments"] = allowsInstallments }
        if let closingDay { payload["closing_day"] = closingDay }
        if let dueDay { payload["due_day"] = dueDay }
        if let status { payload["status"] = status }

        let endpoint = try Endpoint(
            path: "/v1/accounts/\(id)",
            method: .put,
            token: token,
            jsonBody: payload
        )
        return try await client.request(endpoint)
    }

    /// Remove suavemente (soft delete) uma conta
    public func deleteAccount(token: String, id: Int) async throws {
        let endpoint = try Endpoint(
            path: "/v1/accounts/\(id)",
            method: .delete,
            token: token
        )
        try await client.execute(endpoint)
    }
}
