import Foundation

/// Cliente de rede para gerenciamento de categorias na API REST do Cofrinho.
public final class CategoriesAPIService: Sendable {
    public static let shared = CategoriesAPIService()

    private let client: APIClient

    public init(client: APIClient = .shared) {
        self.client = client
    }

    /// Lista todas as categorias ativas do usuário
    public func listCategories(token: String, includeHidden: Bool = false) async throws -> [CategoryModel] {
        var queryItems: [URLQueryItem]? = nil
        if includeHidden {
            queryItems = [URLQueryItem(name: "include_hidden", value: "true")]
        }

        let endpoint = try Endpoint(
            path: "/v1/categories",
            method: .get,
            token: token,
            queryItems: queryItems
        )
        return try await client.request(endpoint)
    }

    /// Cria uma nova categoria personalizada
    public func createCategory(
        token: String,
        name: String,
        icon: String = "tag.fill",
        color: String = "#FF9500"
    ) async throws -> CategoryModel {
        let endpoint = try Endpoint(
            path: "/v1/categories",
            method: .post,
            token: token,
            jsonBody: [
                "name": name,
                "icon": icon,
                "color": color
            ]
        )
        return try await client.request(endpoint)
    }

    /// Atualiza uma categoria existente
    public func updateCategory(
        token: String,
        id: Int,
        name: String? = nil,
        icon: String? = nil,
        color: String? = nil,
        status: String? = nil
    ) async throws -> CategoryModel {
        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if let icon { payload["icon"] = icon }
        if let color { payload["color"] = color }
        if let status { payload["status"] = status }

        let endpoint = try Endpoint(
            path: "/v1/categories/\(id)",
            method: .put,
            token: token,
            jsonBody: payload
        )
        return try await client.request(endpoint)
    }

    /// Deleta suavemente (soft delete) uma categoria
    public func deleteCategory(token: String, id: Int) async throws {
        let endpoint = try Endpoint(
            path: "/v1/categories/\(id)",
            method: .delete,
            token: token
        )
        try await client.execute(endpoint)
    }
}
