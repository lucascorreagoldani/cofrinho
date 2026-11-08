import Foundation

/// Métodos HTTP suportados pela API REST do Cofrinho.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Especificação declarativa de um Endpoint para consumo via APIClient.
public struct Endpoint: Sendable {
    public let path: String
    public let method: HTTPMethod
    public let queryItems: [URLQueryItem]?
    public let headers: [String: String]?
    public let body: Data?
    public let timeoutInterval: TimeInterval

    public init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String]? = nil,
        body: Data? = nil,
        timeoutInterval: TimeInterval = 10
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
    }

    /// Inicializador de conveniência para endpoints autenticados e com payload JSON.
    public init(
        path: String,
        method: HTTPMethod = .get,
        token: String? = nil,
        queryItems: [URLQueryItem]? = nil,
        jsonBody: [String: Any]? = nil,
        timeoutInterval: TimeInterval = 10
    ) throws {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.timeoutInterval = timeoutInterval

        var hdrs: [String: String] = [:]
        if let token, !token.isEmpty {
            hdrs["Authorization"] = "Bearer \(token)"
        }
        if let jsonBody {
            hdrs["Content-Type"] = "application/json"
            self.body = try JSONSerialization.data(withJSONObject: jsonBody)
        } else {
            self.body = nil
        }
        self.headers = hdrs.isEmpty ? nil : hdrs
    }
}

/// Cliente unificado de rede do Cofrinho com suporte nativo a Swift Concurrency,
/// decodificação RFC 9457 Problem Details e mapeamento padronizado de AppErrorProtocol.
public final class APIClient: @unchecked Sendable {
    public static let shared = APIClient()

    /// URL canônica exclusiva da VPS Host Ryzen (porta 3333 no host).
    public let baseURL: URL = URL(string: "http://198.89.99.42:3333")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Executa uma requisição e decodifica a resposta tipada no padrão Codable.
    public func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let request = try buildURLRequest(from: endpoint)
        let data = try await performDataRequest(request)

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch let decodeErr {
            let rawBody = String(data: data, encoding: .utf8) ?? "<corpo não utf-8>"
            AppLogger.shared.error("Falha ao decodificar \(T.self): \(decodeErr). Corpo: \(rawBody)", category: .network)
            throw NetworkError.decodingFailed(reason: "\(decodeErr.localizedDescription) (Payload: \(rawBody.prefix(80)))")
        }
    }

    /// Executa uma requisição sem esperar retorno de payload (ex: DELETE, LOGOUT 204).
    public func execute(_ endpoint: Endpoint) async throws {
        let request = try buildURLRequest(from: endpoint)
        _ = try await performDataRequest(request)
    }

    private func buildURLRequest(from endpoint: Endpoint) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true)
        if let queryItems = endpoint.queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let finalURL = components?.url else {
            throw NetworkError.unknown(reason: "URL inválida para o endpoint: \(endpoint.path)")
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = endpoint.timeoutInterval

        if let headers = endpoint.headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let body = endpoint.body {
            request.httpBody = body
        }

        return request
    }

    private func performDataRequest(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown(reason: "Resposta inválida do servidor")
            }

            if !(200...299).contains(httpResponse.statusCode) {
                let problem = try? JSONDecoder().decode(ProblemDetailsDTO.self, from: data)
                let msg = problem?.detail ?? problem?.title ?? "Erro na requisição (\(httpResponse.statusCode))"

                switch httpResponse.statusCode {
                case 401:
                    if request.url?.path.contains("/login") == true {
                        throw AuthError.invalidCredentials
                    } else {
                        throw AuthError.unauthorized
                    }
                case 409:
                    throw AuthError.accountAlreadyExists(detail: msg)
                case 400:
                    throw AuthError.serverError(message: msg, incidentId: problem?.incidentId)
                default:
                    throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: msg)
                }
            }

            return data
        } catch let appErr as any AppErrorProtocol {
            throw appErr
        } catch let urlErr as URLError {
            if urlErr.code == .cannotConnectToHost || urlErr.code == .networkConnectionLost || urlErr.code == .cannotFindHost {
                throw NetworkError.serverUnreachable(host: "VPS Cofrinho (\(baseURL.host ?? "198.89.99.42"):3333)")
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

