import Foundation

/// Erros relacionados à camada de persistência local (SwiftData / Core Data).
public enum DatabaseError: AppErrorProtocol {
    case saveFailed(reason: String)
    case fetchFailed(reason: String)
    case deleteFailed(reason: String)
    case recordNotFound(id: String)
    case migrationFailed(reason: String)

    public var errorCode: String {
        switch self {
        case .saveFailed: return "DB_001"
        case .fetchFailed: return "DB_002"
        case .deleteFailed: return "DB_003"
        case .recordNotFound: return "DB_004"
        case .migrationFailed: return "DB_005"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Não foi possível salvar os dados financeiros no dispositivo."
        case .fetchFailed:
            return "Não foi possível carregar as informações salvas."
        case .deleteFailed:
            return "Não foi possível excluir o registro selecionado."
        case .recordNotFound(let id):
            return "O registro solicitado (ID: \(id)) não foi encontrado no banco de dados."
        case .migrationFailed:
            return "Ocorreu uma falha ao atualizar o formato dos dados armazenados."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .saveFailed:
            return "Verifique o espaço livre no dispositivo e tente novamente."
        case .fetchFailed:
            return "Tente recarregar a tela ou reiniciar o aplicativo."
        case .deleteFailed:
            return "Tente realizar a operação novamente."
        case .recordNotFound:
            return "O item pode ter sido removido anteriormente."
        case .migrationFailed:
            return "Tente reiniciar o app ou restaurar um backup recente."
        }
    }

    public var debugDetails: String? {
        switch self {
        case .saveFailed(let reason):
            return "[DB_001] Falha ao persistir alterações: \(reason)"
        case .fetchFailed(let reason):
            return "[DB_002] Falha na consulta de dados: \(reason)"
        case .deleteFailed(let reason):
            return "[DB_003] Falha na deleção de registro: \(reason)"
        case .recordNotFound(let id):
            return "[DB_004] Registro inexistente para ID: \(id)"
        case .migrationFailed(let reason):
            return "[DB_005] Falha crítica de migração de schema: \(reason)"
        }
    }
}

