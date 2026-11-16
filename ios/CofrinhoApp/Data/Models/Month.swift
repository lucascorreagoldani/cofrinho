import Foundation

/// Representação fortemente tipada e internacionalizada dos meses do ano no Cofrinho.
/// Totalmente compatível com Swift 6 strict concurrency, CaseIterable, Identifiable, Comparable
/// e integrado à localização Apple com fallback canônico para Português do Brasil.
public enum Month: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case january = 1
    case february = 2
    case march = 3
    case april = 4
    case may = 5
    case june = 6
    case july = 7
    case august = 8
    case september = 9
    case october = 10
    case november = 11
    case december = 12

    public var id: Int { rawValue }

    /// Calendário padrão em Português do Brasil para consistência da interface.
    public static var appLocaleCalendar: Calendar {
        var cal = Calendar.current
        if cal.locale?.language.languageCode?.identifier != "pt" {
            cal.locale = Locale(identifier: "pt_BR")
        }
        return cal
    }

    /// Inicializa a partir de uma data ou componente de data
    public init(date: Date = Date(), calendar: Calendar = .current) {
        let monthNumber = calendar.component(.month, from: date)
        self = Month(rawValue: monthNumber) ?? .january
    }

    /// Nome completo do mês localizado conforme o Locale e Calendário informados.
    /// Utiliza pt_BR por padrão para evitar nomes em inglês quando o sistema/simulador estiver em en_US.
    public func localizedName(calendar: Calendar = Month.appLocaleCalendar) -> String {
        let symbols = calendar.monthSymbols
        let index = rawValue - 1
        if symbols.indices.contains(index) {
            return symbols[index].capitalized
        }
        return defaultFallbackName
    }

    /// Nome abreviado do mês (ex: "Jan", "Fev").
    public func shortName(calendar: Calendar = Month.appLocaleCalendar) -> String {
        let symbols = calendar.shortMonthSymbols
        let index = rawValue - 1
        if symbols.indices.contains(index) {
            return symbols[index].capitalized
        }
        return String(localizedName(calendar: calendar).prefix(3))
    }

    /// Comparação cronológica entre meses
    public static func < (lhs: Month, rhs: Month) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private var defaultFallbackName: String {
        switch self {
        case .january: return "Janeiro"
        case .february: return "Fevereiro"
        case .march: return "Março"
        case .april: return "Abril"
        case .may: return "Maio"
        case .june: return "Junho"
        case .july: return "Julho"
        case .august: return "Agosto"
        case .september: return "Setembro"
        case .october: return "Outubro"
        case .november: return "Novembro"
        case .december: return "Dezembro"
        }
    }
}
