import Testing
import Foundation
@testable import Cofrinho

@Suite("Testes do Subsistema de Erros e Logs")
struct ErrorAndLoggingTests {

    @Test("Validação de códigos e mensagens do DatabaseError")
    func testDatabaseErrorProperties() {
        let saveError = DatabaseError.saveFailed(reason: "Disco cheio")
        #expect(saveError.errorCode == "DB_001")
        #expect(saveError.errorDescription?.contains("salvar") == true)
        #expect(saveError.recoverySuggestion?.isEmpty == false)

        let notFoundError = DatabaseError.recordNotFound(id: "123")
        #expect(notFoundError.errorCode == "DB_004")
        #expect(notFoundError.errorDescription?.contains("123") == true)
    }

    @Test("Validação de códigos e mensagens do NetworkError")
    func testNetworkErrorProperties() {
        let noConnection = NetworkError.noConnection
        #expect(noConnection.errorCode == "NET_002")
        #expect(noConnection.errorDescription?.contains("internet") == true)

        let serverError = NetworkError.serverError(statusCode: 500, message: "Erro interno")
        #expect(serverError.errorCode == "NET_SRV_500")
        #expect(serverError.errorDescription == "Erro interno")
    }

    @Test("Validação de códigos e mensagens do ValidationError")
    func testValidationErrorProperties() {
        let invalidAmount = ValidationError.invalidAmount
        #expect(invalidAmount.errorCode == "VAL_001")
        #expect(invalidAmount.errorDescription?.contains("maior do que zero") == true)

        let emptyTitle = ValidationError.emptyTitle
        #expect(emptyTitle.errorCode == "VAL_002")
    }

    @Test("Validação de códigos e mensagens do SecurityError")
    func testSecurityErrorProperties() {
        let biometryNotAvailable = SecurityError.biometryNotAvailable
        #expect(biometryNotAvailable.errorCode == "SEC_001")
        #expect(biometryNotAvailable.errorDescription?.contains("Face ID / Touch ID") == true)
    }

    @Test("Validação de níveis e categorias de Log")
    func testLogLevelsAndCategories() {
        #expect(LogLevel.debug < LogLevel.error)
        #expect(LogLevel.info < LogLevel.critical)
        #expect(LogCategory.allCases.count == 5)
    }

    @Test("Validação do MockLogService em conformidade com LogServiceProtocol")
    func testMockLogService() {
        final class MockLogger: LogServiceProtocol, @unchecked Sendable {
            var loggedMessages: [String] = []

            func log(
                _ message: String,
                level: LogLevel,
                category: LogCategory,
                file: String,
                function: String,
                line: Int
            ) {
                loggedMessages.append("[\(level.rawValue)] [\(category.rawValue)] \(message)")
            }
        }

        let mock = MockLogger()
        mock.info("Inicializando subsistema", category: .app)
        mock.error("Falha de teste", category: .database)

        #expect(mock.loggedMessages.count == 2)
        #expect(mock.loggedMessages[0].contains("[INFO] [App]"))
        #expect(mock.loggedMessages[1].contains("[ERROR] [Database]"))
    }
}

