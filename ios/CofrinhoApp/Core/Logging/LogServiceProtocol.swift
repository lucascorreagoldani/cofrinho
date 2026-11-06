import Foundation

/// Contrato para serviços de logging no aplicativo, permitindo Inversão de Dependência (DIP)
/// e substituição por Mocks em testes unitários.
public protocol LogServiceProtocol: Sendable {
    func log(
        _ message: String,
        level: LogLevel,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    )

    func debug(
        _ message: String,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    )

    func info(
        _ message: String,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    )

    func warning(
        _ message: String,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    )

    func error(
        _ message: String,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    )

    func critical(
        _ message: String,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    )
}

public extension LogServiceProtocol {
    func debug(
        _ message: String,
        category: LogCategory,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    func info(
        _ message: String,
        category: LogCategory,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    func warning(
        _ message: String,
        category: LogCategory,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }

    func error(
        _ message: String,
        category: LogCategory,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    func critical(
        _ message: String,
        category: LogCategory,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .critical, category: category, file: file, function: function, line: line)
    }
}

