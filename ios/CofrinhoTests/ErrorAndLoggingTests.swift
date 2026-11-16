import Testing
import Foundation
import SwiftUI
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

        let serverError = NetworkError.serverError(statusCode: 500, message: "Erro interno", incidentId: "INC-999")
        #expect(serverError.errorCode == "NET_SRV_500")
        #expect(serverError.errorDescription?.contains("Erro interno") == true)
        #expect(serverError.errorDescription?.contains("INC-999") == true)
        #expect(serverError.recoverySuggestion?.contains("INC-999") == true)
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
        #expect(LogCategory.allCases.count == 7)
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

    @Test("Validação do Enum Month internacionalizado e ordenável")
    func testMonthEnum() {
        #expect(Month.allCases.count == 12)
        #expect(Month.january < Month.december)
        #expect(Month.november.rawValue == 11)
        #expect(Month(rawValue: 2) == .february)

        for month in Month.allCases {
            #expect(!month.localizedName().isEmpty)
            #expect(!month.shortName().isEmpty)
        }
    }

    @Test("Validação dos Enums Canônicos de Domínio")
    func testDomainEnums() {
        #expect(RecordStatus.allCases.count == 3)
        #expect(TransactionFilterStatus.allCases.count == 3)
        #expect(TransactionType.allCases.count == 2)
        #expect(AccountType.allCases.count == 5)
        #expect(DeleteCascadeMode.allCases.count == 2)
        #expect(SyncStatus.allCases.count == 4)

        #expect(AccountType.creditCard.supportsInstallmentsByDefault == true)
        #expect(AccountType.pix.supportsInstallmentsByDefault == false)
        #expect(AccountType(rawValue: "credit_card") == .creditCard)
        #expect(TransactionFilterStatus.all.localizedTitle.contains("ocultas"))
    }

    @Test("Validação de FormatStyle BRL e Color Hex")
    func testFormattersAndColorHex() {
        let decValue = Decimal(string: "1234.56")!
        let formattedDec = decValue.brlCurrencyFormatted
        #expect(formattedDec.contains("1.234,56"))
        #expect(formattedDec.contains("R$"))

        let dblValue = 99.9
        #expect(dblValue.brlCurrencyFormatted.contains("99,90"))

        let date = Date(timeIntervalSince1970: 1_794_000_000)
        #expect(!date.brShortDateFormatted.isEmpty)

        // Valida que inicializadores hex de 3, 6 e 8 dígitos resolvem sem erro
        _ = Color(hex: "#FF9500")
        _ = Color(hex: "F90")
        _ = Color(hex: "80FF9500")
        _ = Color(hex: "invalid", defaultColor: .blue)
    }
}

