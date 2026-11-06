import Foundation

/// Cliente de rede para gerenciamento de categorias na API REST do Cofrinho.
public final class CategoriesAPIService: @unchecked Sendable {
    public static let shared = CategoriesAPIService()

    public let baseURL: URL = URL(string: "http://198.89.99.42:3333")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Lista todas as categorias ativas do usuário
    public func listCategories(token: String, includeHidden: Bool = false) async throws -> [CategoryModel] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/categories"), resolvingAgainstBaseURL: true)!
        if includeHidden {
            components.queryItems = [URLQueryItem(name: "include_hidden", value: "true")]
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        return try await performRequest(request)
    }

    /// Cria uma nova categoria personalizada
    public func createCategory(
        token: String,
        name: String,
        icon: String = "tag.fill",
        color: String = "#FF9500"
    ) async throws -> CategoryModel {
        let endpoint = baseURL.appendingPathComponent("/v1/categories")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let payload: [String: Any] = [
            "name": name,
            "icon": icon,
            "color": color
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        return try await performRequest(request)
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
        let endpoint = baseURL.appendingPathComponent("/v1/categories/\(id)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if let icon { payload["icon"] = icon }
        if let color { payload["color"] = color }
        if let status { payload["status"] = status }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await performRequest(request)
    }

    /// Deleta suavemente (soft delete) uma categoria
    public func deleteCategory(token: String, id: Int) async throws {
        let endpoint = baseURL.appendingPathComponent("/v1/categories/\(id)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "Falha ao excluir categoria")
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
                let msg = problem?.detail ?? problem?.title ?? "Falha na requisição de categorias"
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

