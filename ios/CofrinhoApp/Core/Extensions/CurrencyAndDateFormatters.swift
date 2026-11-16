import Foundation

public extension Decimal {
    /// Formata o valor Decimal no padrão monetário Real Brasileiro (R$ 0,00) usando FormatStyle nativo.
    var brlCurrencyFormatted: String {
        self.formatted(
            .currency(code: "BRL")
                .locale(Locale(identifier: "pt_BR"))
        )
    }
}

public extension Double {
    /// Formata o valor Double no padrão monetário Real Brasileiro (R$ 0,00) usando FormatStyle nativo.
    var brlCurrencyFormatted: String {
        self.formatted(
            .currency(code: "BRL")
                .locale(Locale(identifier: "pt_BR"))
        )
    }
}

public extension Date {
    /// Formata a data no padrão brasileiro (DD/MM/AAAA) usando FormatStyle nativo sem alocação de DateFormatter.
    var brShortDateFormatted: String {
        self.formatted(
            .dateTime
                .day(.twoDigits)
                .month(.twoDigits)
                .year()
                .locale(Locale(identifier: "pt_BR"))
        )
    }
}
