import Foundation

/// Categorias de log do sistema para rastreamento segmentado no Console da Apple.
public enum LogCategory: String, Sendable, CaseIterable {
    case app = "App"
    case database = "Database"
    case network = "Network"
    case security = "Security"
    case ui = "UI"

    public var description: String {
        rawValue
    }
}

/// Níveis de severidade de log alinhados aos padrões do os.Logger.
public enum LogLevel: String, Sendable, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"

    private var priority: Int {
        switch self {
        case .debug: return 1
        case .info: return 2
        case .warning: return 3
        case .error: return 4
        case .critical: return 5
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

