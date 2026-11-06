import Foundation

/// Erros relacionados à comunicação de rede e chamadas de API REST.
public enum NetworkError: AppErrorProtocol {
    case invalidURL(url: String)
    case noConnection
    case timeout
    case serverUnreachable(host: String)
    case serverError(statusCode: Int, message: String?)
    case decodingFailed(reason: String)
    case unauthorized
    case unknown(reason: String)

    public var errorCode: String {
        switch self {
        case .invalidURL: return "NET_001"
        case .noConnection: return "NET_002"
        case .timeout: return "NET_003"
        case .serverUnreachable: return "NET_005"
        case .serverError(let code, _): return "NET_SRV_\(code)"
        case .decodingFailed: return "NET_004"
        case .unauthorized: return "NET_401"
        case .unknown: return "NET_999"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "O endereço de rede solicitado é inválido."
        case .noConnection:
            return "Seu dispositivo está sem conexão com a internet."
        case .timeout:
            return "O tempo de resposta do servidor expirou."
        case .serverUnreachable(let host):
            return "O servidor do Cofrinho está inacessível no momento (\(host))."
        case .serverError(let code, let msg):
            if let msg, !msg.isEmpty {
                return msg
            }
            return "O servidor retornou um erro inesperado (Código \(code))."
        case .decodingFailed:
            return "Ocorreu um erro ao processar os dados recebidos."
        case .unauthorized:
            return "Sessão expirada ou não autorizada. Faça login novamente."
        case .unknown:
            return "Ocorreu uma falha inesperada de comunicação de rede."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noConnection:
            return "Verifique se o Wi-Fi ou seus dados móveis (4G/5G) estão ativos e tente novamente."
        case .serverUnreachable:
            return "O servidor backend pode estar offline ou inacessível nesta rede. Você pode tentar novamente ou alternar o servidor nas configurações de rede."
        case .timeout:
            return "Sua conexão pode estar lenta. Aguarde alguns instantes e tente novamente."
        case .unauthorized:
            return "Acesse novamente sua conta para revalidar as credenciais."
        case .serverError:
            return "Nossos servidores estão indisponíveis temporariamente. Tente em alguns minutos."
        default:
            return "Tente novamente mais tarde."
        }
    }

    public var debugDetails: String? {
        switch self {
        case .invalidURL(let url):
            return "[NET_001] URL inválida: \(url)"
        case .noConnection:
            return "[NET_002] Conexão indisponível (URLError.notConnectedToInternet)"
        case .timeout:
            return "[NET_003] Timeout de requisição"
        case .serverUnreachable(let host):
            return "[NET_005] Servidor inacessível / conexão recusada: \(host)"
        case .serverError(let code, let msg):
            return "[NET_SRV_\(code)] Resposta do servidor HTTP \(code): \(msg ?? "Sem mensagem")"
        case .decodingFailed(let reason):
            return "[NET_004] Falha no JSONDecoder: \(reason)"
        case .unauthorized:
            return "[NET_401] Token ausente, inválido ou expirado"
        case .unknown(let reason):
            return "[NET_999] Falha genérica: \(reason)"
        }
    }
}
