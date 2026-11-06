import Foundation

/// Protocolo base para todos os erros da aplicação, garantindo compatibilidade com SwiftUI,
/// Swift 6 Concurrency, asserções de testes e apresentação amigável para o usuário.
public protocol AppErrorProtocol: LocalizedError, Sendable, Identifiable, Equatable {
    /// Identificador único para uso em modais e alertas do SwiftUI (.alert(item: ...))
    var id: String { get }

    /// Código único de erro técnico (ex: DB_001, NET_404, VAL_001) para rastreabilidade
    var errorCode: String { get }

    /// Mensagem em linguagem amigável voltada para o usuário final
    var errorDescription: String? { get }

    /// Ação ou sugestão de recuperação sugerida ao usuário
    var recoverySuggestion: String? { get }

    /// Detalhes técnicos para diagnóstico e registro nos logs
    var debugDetails: String? { get }
}

public extension AppErrorProtocol {
    var id: String {
        "\(errorCode)_\(String(describing: self))"
    }

    var recoverySuggestion: String? {
        "Ocorreu um erro na sua ação mais recente, por favor tente novamente."
    }

    var debugDetails: String? {
        errorDescription
    }
}
