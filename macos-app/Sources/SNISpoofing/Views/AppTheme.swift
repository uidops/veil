import SwiftUI

enum AppTheme {
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 10
    static let pageSpacing: CGFloat = 20
    /// Signal colors: mint means healthy/active; coral means action/attention.
    static let cyan = Color(.sRGB, red: 0.12, green: 0.76, blue: 0.58, opacity: 1)
    static let indigo = Color(.sRGB, red: 0.94, green: 0.31, blue: 0.25, opacity: 1)

    static func background(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.045, green: 0.055, blue: 0.052, opacity: 1),
                    Color(.sRGB, red: 0.065, green: 0.073, blue: 0.068, opacity: 1),
                    Color(.sRGB, red: 0.040, green: 0.048, blue: 0.047, opacity: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(.sRGB, red: 0.965, green: 0.955, blue: 0.925, opacity: 1),
                Color(.sRGB, red: 0.935, green: 0.925, blue: 0.895, opacity: 1),
                Color(.sRGB, red: 0.955, green: 0.947, blue: 0.918, opacity: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func sidebarBackground(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.070, green: 0.080, blue: 0.075, opacity: 1),
                    Color(.sRGB, red: 0.035, green: 0.043, blue: 0.041, opacity: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color(.sRGB, red: 0.975, green: 0.965, blue: 0.938, opacity: 1),
                Color(.sRGB, red: 0.925, green: 0.915, blue: 0.882, opacity: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(.sRGB, red: 0.090, green: 0.105, blue: 0.098, opacity: 0.96) : Color(.sRGB, red: 0.985, green: 0.978, blue: 0.952, opacity: 0.92)
    }

    static func elevatedFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(.sRGB, red: 0.125, green: 0.140, blue: 0.132, opacity: 1) : Color(.sRGB, red: 1, green: 0.995, blue: 0.978, opacity: 1)
    }

    static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.30) : Color(.sRGB, red: 0.885, green: 0.875, blue: 0.842, opacity: 0.72)
    }

    static func subtleFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    static func hoverFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.070) : Color.black.opacity(0.075)
    }

    static func stroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.115) : Color.black.opacity(0.14)
    }

    static func faintStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.060) : Color.black.opacity(0.095)
    }

    static func cardShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.08)
    }

    /// Connect button fill (flat, matches cards).
    static func connectFill(for scheme: ColorScheme) -> Color {
        indigo
    }

    static func connectShadow(for scheme: ColorScheme) -> Color {
        indigo.opacity(scheme == .dark ? 0.42 : 0.24)
    }

    static func chromeFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(.sRGB, red: 0.045, green: 0.052, blue: 0.049, opacity: 0.96)
            : Color(.sRGB, red: 0.975, green: 0.965, blue: 0.935, opacity: 0.96)
    }
}
