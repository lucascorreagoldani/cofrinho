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

/// Coordenador isolado que evita chamadas simultâneas duplicadas ao endpoint /v1/auth/refresh.
private actor TokenRefreshCoordinator {
    private var ongoingTask: Task<String?, Never>?

    func refreshIfNeeded(
        using session: URLSession,
        baseURL: URL
    ) async -> String? {
        if let existingTask = ongoingTask {
            return await existingTask.value
        }

        let task = Task<String?, Never> {
            await performRefresh(using: session, baseURL: baseURL)
        }
        ongoingTask = task
        let result = await task.value
        ongoingTask = nil
        return result
    }

    private func performRefresh(using session: URLSession, baseURL: URL) async -> String? {
        guard let savedRefreshToken = KeychainHelper.shared.read(key: "cofrinho_refresh_token")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !savedRefreshToken.isEmpty else {
            return nil
        }

        var refreshRequest = URLRequest(url: baseURL.appendingPathComponent("/v1/auth/refresh"))
        refreshRequest.httpMethod = HTTPMethod.post.rawValue
        refreshRequest.timeoutInterval = 10
        refreshRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        refreshRequest.httpBody = try? JSONSerialization.data(withJSONObject: [
            "refresh_token": savedRefreshToken
        ])

        do {
            let (data, response) = try await session.data(for: refreshRequest)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let dto = try JSONDecoder().decode(TokenRefreshResponseDTO.self, from: data)
            KeychainHelper.shared.save(key: "cofrinho_jwt_token", value: dto.accessToken)
            if let rotatedRefresh = dto.refreshToken, !rotatedRefresh.isEmpty {
                KeychainHelper.shared.save(key: "cofrinho_refresh_token", value: rotatedRefresh)
            }
            AppLogger.shared.info("Access token renovado silenciosamente pelo interceptor APIClient.", category: .security)
            return dto.accessToken
        } catch {
            AppLogger.shared.warning("Falha na renovação silenciosa do token no APIClient: \(error.localizedDescription)", category: .security)
            return nil
        }
    }
}

/// Cliente unificado de rede do Cofrinho com suporte nativo a Swift Concurrency,
/// renovação automática de sessão (interceptor pré-request e retry em HTTP 401),
/// decodificação RFC 9457 Problem Details e mapeamento padronizado de AppErrorProtocol.
public final class APIClient: @unchecked Sendable {
    public static let shared = APIClient()

    /// URL canônica exclusiva da VPS Host Ryzen (porta 3333 no host).
    public let baseURL: URL = URL(string: "http://198.89.99.42:3333")!
    private let session: URLSession
    private let refreshCoordinator = TokenRefreshCoordinator()

    private let tokenKey = "cofrinho_jwt_token"

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
        var preparedRequest = request
        let shouldAutoRefresh = isEligibleForAutoRefresh(preparedRequest)

        if shouldAutoRefresh {
            if let latestToken = KeychainHelper.shared.read(key: tokenKey), !latestToken.isEmpty {
                if isJWTExpired(latestToken), let renewed = await attemptSilentTokenRefresh() {
                    preparedRequest.setValue("Bearer \(renewed)", forHTTPHeaderField: "Authorization")
                } else {
                    preparedRequest.setValue("Bearer \(latestToken)", forHTTPHeaderField: "Authorization")
                }
            } else if let currentAuth = preparedRequest.value(forHTTPHeaderField: "Authorization"),
                      currentAuth.hasPrefix("Bearer ") {
                let rawToken = String(currentAuth.dropFirst("Bearer ".count))
                if isJWTExpired(rawToken), let renewed = await attemptSilentTokenRefresh() {
                    preparedRequest.setValue("Bearer \(renewed)", forHTTPHeaderField: "Authorization")
                }
            }
        }

        do {
            var (data, response) = try await session.data(for: preparedRequest)

            guard var httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown(reason: "Resposta inválida do servidor")
            }

            // Interceptor reativo: se a VPS retornou 401 e a rota é elegível, renova via Refresh Token e tenta 1x novamente
            if httpResponse.statusCode == 401, shouldAutoRefresh, let renewedToken = await attemptSilentTokenRefresh() {
                preparedRequest.setValue("Bearer \(renewedToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await session.data(for: preparedRequest)
                if let retryHttp = retryResponse as? HTTPURLResponse {
                    data = retryData
                    httpResponse = retryHttp
                }
            }

            if !(200...299).contains(httpResponse.statusCode) {
                let problem = try? JSONDecoder().decode(ProblemDetailsDTO.self, from: data)
                let msg = problem?.detail ?? problem?.title ?? "Erro na requisição (\(httpResponse.statusCode))"
                let isAuthRoute = preparedRequest.url?.path.contains("/auth/") == true

                switch httpResponse.statusCode {
                case 401:
                    if preparedRequest.url?.path.contains("/login") == true {
                        throw AuthError.invalidCredentials
                    } else {
                        throw AuthError.unauthorized
                    }
                case 409:
                    if isAuthRoute {
                        throw AuthError.accountAlreadyExists(detail: msg)
                    } else {
                        throw ValidationError.custom(message: msg)
                    }
                case 400:
                    if isAuthRoute {
                        throw AuthError.serverError(message: msg, incidentId: problem?.incidentId)
                    } else {
                        throw ValidationError.custom(message: msg)
                    }
                default:
                    throw NetworkError.serverError(
                        statusCode: httpResponse.statusCode,
                        message: msg,
                        incidentId: problem?.incidentId
                    )
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

    private func isEligibleForAutoRefresh(_ request: URLRequest) -> Bool {
        guard let authHeader = request.value(forHTTPHeaderField: "Authorization"),
              authHeader.hasPrefix("Bearer ") else {
            return false
        }
        let path = request.url?.path ?? ""
        if path.contains("/auth/login") ||
           path.contains("/auth/register") ||
           path.contains("/auth/refresh") ||
           path.contains("/auth/logout") {
            return false
        }
        return true
    }

    private func attemptSilentTokenRefresh() async -> String? {
        await refreshCoordinator.refreshIfNeeded(using: session, baseURL: baseURL)
    }

    private func isJWTExpired(_ jwt: String) -> Bool {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return false }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = (4 - base64.count % 4) % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: padding))
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return false
        }

        return Date().timeIntervalSince1970 >= (exp - 10)
    }
}
