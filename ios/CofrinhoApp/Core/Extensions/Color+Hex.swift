import SwiftUI

public extension Color {
    /// Inicializa uma cor SwiftUI a partir de uma string hexadecimal (suporta 3, 6 e 8 dígitos RGB/ARGB).
    init(hex: String, defaultColor: Color = .orange) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard !clean.isEmpty, Scanner(string: clean).scanHexInt64(&int) else {
            self = defaultColor
            return
        }

        let a, r, g, b: UInt64
        switch clean.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            self = defaultColor
            return
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}
