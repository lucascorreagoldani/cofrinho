import Foundation

/// Modelos de resposta da API do Cofrinho
public struct UserProfileDTO: Codable, Sendable, Identifiable {
    public let id: Int
    public let username: String
    public let email: String
    public let firstIp: String?
    public let lastIp: String?
    public let firstLogin: Int?
    public let lastLogin: Int?
    public let registeredAt: Int

    enum CodingKeys: String, CodingKey {
        case id, username, email
        case firstIp = "first_ip"
        case lastIp = "last_ip"
        case firstLogin = "first_login"
        case lastLogin = "last_login"
        case registeredAt = "registered_at"
    }

    /// Data convertida a partir do timestamp numérico em epoch ms.
    public var registrationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(registeredAt) / 1000.0)
    }

    public var lastLoginDate: Date? {
        guard let lastLogin else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastLogin) / 1000.0)
    }
}

public struct UserPreferencesDTO: Codable, Sendable {
    public let userId: Int
    public var fastLogin: Bool
    public var verification: Bool
    public let updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case fastLogin = "fast_login"
        case verification
        case updatedAt = "updated_at"
    }
}

public struct AuthSessionDTO: Codable, Sendable {
    public let id: String
    public let status: String
    public let expiresAt: Int

    enum CodingKeys: String, CodingKey {
        case id, status
        case expiresAt = "expires_at"
    }
}

public struct LoginResponseDTO: Codable, Sendable {
    public let user: UserProfileDTO
    public let session: AuthSessionDTO
    public let token: String
}

public struct RegisterResponseDTO: Codable, Sendable {
    public let message: String
    public let user: UserProfileDTO
}

public struct ProblemDetailsDTO: Codable, Sendable {
    public let type: String?
    public let title: String?
    public let status: Int?
    public let detail: String?
    public let code: String?
    public let incidentId: String?
    public let timestamp: Int?
}

/// Cliente de rede para os serviços de autenticação e preferências da API do Cofrinho.
public final class AuthAPIService: @unchecked Sendable {
    public static let shared = AuthAPIService()

    /// URL base da API (Porta 3333 no host conforme topologia padrão)
    public var baseURL: URL = URL(string: "http://127.0.0.1:3333")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Autenticação

    public func register(username: String, email: String, password: String) async throws -> RegisterResponseDTO {
        let endpoint = baseURL.appendingPathComponent("/v1/auth/register")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = [
            "username": username,
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        return try await performRequest(request)
    }

    public func login(login: String, password: String, fastLogin: Bool) async throws -> LoginResponseDTO {
        let endpoint = baseURL.appendingPathComponent("/v1/auth/login")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "login": login,
            "password": password,
            "fast_login": fastLogin
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        return try await performRequest(request)
    }

    public func logout(token: String) async throws {
        let endpoint = baseURL.appendingPathComponent("/v1/auth/logout")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "Falha ao deslogar da sessão")
        }
    }

    // MARK: - Usuários & Preferências

    public func getProfile(token: String) async throws -> UserProfileDTO {
        let endpoint = baseURL.appendingPathComponent("/v1/users/me")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(request)
    }

    public func getPreferences(token: String) async throws -> UserPreferencesDTO {
        let endpoint = baseURL.appendingPathComponent("/v1/users/me/preferences")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(request)
    }

    public func updatePreferences(token: String, fastLogin: Bool? = nil, verification: Bool? = nil) async throws -> UserPreferencesDTO {
        let endpoint = baseURL.appendingPathComponent("/v1/users/me/preferences")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var payload: [String: Any] = [:]
        if let fastLogin { payload["fast_login"] = fastLogin }
        if let verification { payload["verification"] = verification }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
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
                let msg = problem?.detail ?? problem?.title ?? "Erro na requisição"

                switch httpResponse.statusCode {
                case 401:
                    throw AuthError.invalidCredentials
                case 409:
                    throw AuthError.accountAlreadyExists(detail: msg)
                case 400:
                    throw AuthError.serverError(message: msg, incidentId: problem?.incidentId)
                default:
                    throw AuthError.serverError(message: msg, incidentId: problem?.incidentId)
                }
            }

            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch let err as any AppErrorProtocol {
            throw err
        } catch let urlErr as URLError {
            if urlErr.code == .notConnectedToInternet || urlErr.code == .cannotConnectToHost {
                throw NetworkError.noConnection
            } else if urlErr.code == .timedOut {
                throw NetworkError.timeout
            } else {
                throw NetworkError.unknown(reason: urlErr.localizedDescription)
            }
        } catch {
            throw NetworkError.decodingFailed(reason: error.localizedDescription)
        }
    }
}
