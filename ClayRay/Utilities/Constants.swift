import SwiftUI

enum ClayColors {
    // Light mode clay palette
    static let terracotta = Color(red: 0.80, green: 0.46, blue: 0.35)
    static let terracottaDark = Color(red: 0.65, green: 0.35, blue: 0.25)
    static let oceanTeal = Color(red: 0.22, green: 0.45, blue: 0.48)
    static let oceanTealDark = Color(red: 0.15, green: 0.35, blue: 0.38)

    // Dark mode stone palette
    static let stoneGray = Color(red: 0.55, green: 0.53, blue: 0.50)
    static let stoneGrayDark = Color(red: 0.40, green: 0.38, blue: 0.36)
    static let oceanStone = Color(red: 0.30, green: 0.38, blue: 0.42)

    // UV level glow colors
    static let uvLow = Color(red: 0.65, green: 0.60, blue: 0.85)        // Cool lavender
    static let uvModerate = Color(red: 0.95, green: 0.80, blue: 0.40)    // Warm golden
    static let uvHigh = Color(red: 0.95, green: 0.45, blue: 0.25)        // Orange-red
    static let uvVeryHigh = Color(red: 0.95, green: 0.25, blue: 0.15)    // Intense red
    static let uvExtreme = Color(red: 1.00, green: 0.15, blue: 0.10)     // Blazing

    // Panel and background
    static let panelBackground = Color(red: 0.94, green: 0.90, blue: 0.85)
    static let panelBackgroundDark = Color(red: 0.20, green: 0.19, blue: 0.18)
    static let deskLight = Color(red: 0.96, green: 0.93, blue: 0.89)
    static let deskDark = Color(red: 0.12, green: 0.11, blue: 0.10)

    static func uvColor(for uvi: Double) -> Color {
        switch uvi {
        case ..<3: return uvLow
        case 3..<6: return uvModerate
        case 6..<8: return uvHigh
        case 8..<11: return uvVeryHigh
        default: return uvExtreme
        }
    }

    static func uvNSColor(for uvi: Double) -> NSColor {
        switch uvi {
        case ..<3: return NSColor(red: 0.65, green: 0.60, blue: 0.85, alpha: 1)
        case 3..<6: return NSColor(red: 0.95, green: 0.80, blue: 0.40, alpha: 1)
        case 6..<8: return NSColor(red: 0.95, green: 0.45, blue: 0.25, alpha: 1)
        case 8..<11: return NSColor(red: 0.95, green: 0.25, blue: 0.15, alpha: 1)
        default: return NSColor(red: 1.00, green: 0.15, blue: 0.10, alpha: 1)
        }
    }
}

enum ClayFonts {
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum AppConstants {
    static let defaultWindowWidth: CGFloat = 900
    static let defaultWindowHeight: CGFloat = 600
    static let refreshInterval: TimeInterval = 300  // 5 minutes
    static let diveAnimationDuration: TimeInterval = 1.2
    static let globeRadius: CGFloat = 1.0
    static let cameraDistance: CGFloat = 3.5
}
