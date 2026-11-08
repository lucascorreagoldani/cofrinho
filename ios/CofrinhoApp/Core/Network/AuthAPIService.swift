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

public struct LoginResponseDTO: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String?
    public let expiresIn: Int?
    public let user: UserProfileDTO
    public let session: AuthSessionDTO

    public var token: String { accessToken }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
        case session
        case token
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.user = try container.decode(UserProfileDTO.self, forKey: .user)
        self.session = try container.decode(AuthSessionDTO.self, forKey: .session)
        self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        self.tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        self.expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)

        if let access = try container.decodeIfPresent(String.self, forKey: .accessToken) {
            self.accessToken = access
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .token) {
            self.accessToken = legacy
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.accessToken,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Token de acesso ausente na resposta da API")
            )
        }
    }
}

public struct RegisterResponseDTO: Decodable, Sendable {
    public let user: UserProfileDTO
    public let message: String?

    public init(user: UserProfileDTO, message: String? = nil) {
        self.user = user
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        // Suporta resposta direta do Fastify (retorna o UserProfileDTO direto no 201 Created)
        if let directUser = try? UserProfileDTO(from: decoder) {
            self.user = directUser
            self.message = "Conta criada com sucesso"
            return
        }

        // Suporta resposta envelopada com { user, message }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.user = try container.decode(UserProfileDTO.self, forKey: .user)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    enum CodingKeys: String, CodingKey {
        case user
        case message
    }
}

public struct TokenRefreshResponseDTO: Decodable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
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
/// Conecta-se exclusivamente ao backend de produção na VPS dedicada (198.89.99.42:3333).
public final class AuthAPIService: Sendable {
    public static let shared = AuthAPIService()

    private let client: APIClient

    public init(client: APIClient = .shared) {
        self.client = client
        // Limpa qualquer resquício de URL local ou alternativa salva anteriormente
        UserDefaults.standard.removeObject(forKey: "cofrinho_api_base_url")
    }

    // MARK: - Autenticação

    public func register(username: String, email: String, password: String) async throws -> RegisterResponseDTO {
        let endpoint = try Endpoint(
            path: "/v1/auth/register",
            method: .post,
            jsonBody: [
                "username": username,
                "email": email,
                "password": password
            ]
        )
        return try await client.request(endpoint)
    }

    public func login(login: String, password: String, fastLogin: Bool) async throws -> LoginResponseDTO {
        let endpoint = try Endpoint(
            path: "/v1/auth/login",
            method: .post,
            jsonBody: [
                "login": login,
                "password": password,
                "fast_login": fastLogin
            ]
        )
        return try await client.request(endpoint)
    }

    public func refreshToken(refreshToken: String) async throws -> TokenRefreshResponseDTO {
        let endpoint = try Endpoint(
            path: "/v1/auth/refresh",
            method: .post,
            jsonBody: [
                "refresh_token": refreshToken
            ]
        )
        return try await client.request(endpoint)
    }

    public func logout(token: String) async throws {
        let endpoint = try Endpoint(
            path: "/v1/auth/logout",
            method: .post,
            token: token
        )
        try await client.execute(endpoint)
    }

    // MARK: - Usuários & Preferências

    public func getProfile(token: String) async throws -> UserProfileDTO {
        let endpoint = try Endpoint(
            path: "/v1/users/me",
            method: .get,
            token: token
        )
        return try await client.request(endpoint)
    }

    public func getPreferences(token: String) async throws -> UserPreferencesDTO {
        let endpoint = try Endpoint(
            path: "/v1/users/me/preferences",
            method: .get,
            token: token
        )
        return try await client.request(endpoint)
    }

    public func updatePreferences(token: String, fastLogin: Bool? = nil, verification: Bool? = nil) async throws -> UserPreferencesDTO {
        var payload: [String: Any] = [:]
        if let fastLogin { payload["fast_login"] = fastLogin }
        if let verification { payload["verification"] = verification }

        let endpoint = try Endpoint(
            path: "/v1/users/me/preferences",
            method: .patch,
            token: token,
            jsonBody: payload
        )
        return try await client.request(endpoint)
    }
}
