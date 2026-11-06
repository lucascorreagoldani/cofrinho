import Foundation
import OSLog

/// Implementação de alta performance e thread-safe do LogServiceProtocol utilizando o Unified Logging System (os.Logger).
public final class AppLogger: LogServiceProtocol, @unchecked Sendable {
    public static let shared = AppLogger()

    private let subsystem: String
    private let loggers: [LogCategory: os.Logger]

    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.lucas.cofrinho") {
        self.subsystem = subsystem

        var createdLoggers: [LogCategory: os.Logger] = [:]
        for category in LogCategory.allCases {
            createdLoggers[category] = os.Logger(subsystem: subsystem, category: category.rawValue)
        }
        self.loggers = createdLoggers
    }

    public func log(
        _ message: String,
        level: LogLevel,
        category: LogCategory,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard let logger = loggers[category] else { return }

        let formattedMessage = "[\(file):\(line)] \(function) -> \(message)"

        switch level {
        case .debug:
            logger.debug("\(formattedMessage, privacy: .public)")
        case .info:
            logger.info("\(formattedMessage, privacy: .public)")
        case .warning:
            logger.warning("\(formattedMessage, privacy: .public)")
        case .error:
            logger.error("\(formattedMessage, privacy: .public)")
        case .critical:
            logger.fault("\(formattedMessage, privacy: .public)")
        }
    }
}

