import Testing
import Foundation
@testable import Cofrinho

@Suite("Testes de Erros de Autenticação e Validação")
struct AuthErrorTests {

    @Test("Validação de códigos e mensagens do AuthError")
    func testAuthErrorProperties() {
        let credsError = AuthError.invalidCredentials
        #expect(credsError.errorCode == "AUTH_001")
        #expect(credsError.errorDescription?.contains("Usuário/e-mail ou senha") == true)
        #expect(credsError.recoverySuggestion?.isEmpty == false)

        let emptyError = AuthError.emptyFields
        #expect(emptyError.errorCode == "AUTH_002")

        let usernameError = AuthError.usernameTooShort
        #expect(usernameError.errorCode == "AUTH_003")
        #expect(usernameError.errorDescription?.contains("3 caracteres") == true)

        let emailError = AuthError.invalidEmailFormat
        #expect(emailError.errorCode == "AUTH_004")

        let passShort = AuthError.passwordTooShort
        #expect(passShort.errorCode == "AUTH_005")

        let passComplexity = AuthError.passwordRequiresComplexity
        #expect(passComplexity.errorCode == "AUTH_006")

        let mismatch = AuthError.passwordsDoNotMatch
        #expect(mismatch.errorCode == "AUTH_007")

        let conflict = AuthError.accountAlreadyExists(detail: "Nome de usuário já em uso")
        #expect(conflict.errorCode == "AUTH_008")
        #expect(conflict.errorDescription == "Nome de usuário já em uso")

        let serverErr = AuthError.serverError(message: "Falha interna", incidentId: "INC-12345")
        #expect(serverErr.errorCode == "AUTH_500")
        #expect(serverErr.errorDescription?.contains("INC-12345") == true)
    }

    @Test("Conformidade com AppErrorProtocol e LocalizedError")
    func testAppErrorProtocolConformance() {
        let error: any AppErrorProtocol = AuthError.invalidCredentials
        #expect(error.id.starts(with: "AUTH_001"))
        #expect(error.recoverySuggestion != nil)
    }
}

