import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

// MARK: - Color Helpers

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:  (a,r,g,b) = (255,(int>>8)*17,(int>>4 & 0xF)*17,(int & 0xF)*17)
        case 6:  (a,r,g,b) = (255,int>>16,int>>8 & 0xFF,int & 0xFF)
        case 8:  (a,r,g,b) = (int>>24,int>>16 & 0xFF,int>>8 & 0xFF,int & 0xFF)
        default: (a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
    func toHex() -> String {
        let u = UIColor(self); var r,g,b,a: CGFloat; r=0;g=0;b=0;a=0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}

struct AuraThemePalette {
    var backgroundStartHex: String
    var backgroundEndHex:   String
    var accentStartHex:     String
    var accentEndHex:       String

    var backgroundStart: Color { Color(hex: backgroundStartHex) }
    var backgroundEnd:   Color { Color(hex: backgroundEndHex) }
    var accentStart:     Color { Color(hex: accentStartHex) }
    var accentEnd:       Color { Color(hex: accentEndHex) }

    static let fallback = AuraThemePalette(
        backgroundStartHex: "08111F",
        backgroundEndHex: "1B2A41",
        accentStartHex: "0EA5A4",
        accentEndHex: "F59E0B"
    )

    static func from(themeJSON: String) -> AuraThemePalette {
        guard let d = themeJSON.data(using: .utf8),
              let t = try? JSONDecoder().decode(WidgetGradientTheme.self, from: d) else {
            return .fallback
        }
        return .init(
            backgroundStartHex: t.c1,
            backgroundEndHex: t.c2,
            accentStartHex: t.n1,
            accentEndHex: t.n2
        )
    }

    static var current: AuraThemePalette {
        from(themeJSON: UserDefaults.standard.string(forKey: "widgetThemeJSON") ?? "")
    }
}

struct InAppBannerPayload: Equatable {
    var title: String
    var message: String
}

struct AuraDesignTokens {
    struct Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
    }

    struct Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    struct Stroke {
        static let subtle: CGFloat = 1
    }

    struct Typography {
        static let eyebrow = Font.system(size: 10, weight: .bold, design: .rounded)
        static let title = Font.system(size: 22, weight: .black, design: .rounded)
        static let subtitle = Font.system(size: 13, weight: .semibold)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 11, weight: .semibold)
    }

    struct Elevation {
        static let cardShadowRadius: CGFloat = 16
        static let cardShadowY: CGFloat = 8
    }
}

struct AuraSoftPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(AuraMotion.quick, value: configuration.isPressed)
    }
}

extension View {
    func auraGlassCard(radius: CGFloat = AuraDesignTokens.Radius.md) -> some View {
        let p = AuraThemePalette.current
        return self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [p.accentStart.opacity(0.09), p.accentEnd.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: AuraDesignTokens.Stroke.subtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(p.accentStart.opacity(0.18), lineWidth: 0.6)
            )
            .shadow(
                color: .black.opacity(0.18),
                radius: AuraDesignTokens.Elevation.cardShadowRadius,
                y: AuraDesignTokens.Elevation.cardShadowY
            )
            .shadow(
                color: p.accentStart.opacity(0.1),
                radius: 22,
                y: 10
            )
    }
}

struct AuraAtmosphericBackground: View {
    var body: some View {
        let palette = AuraThemePalette.current
        ZStack {
            LinearGradient(
                colors: [palette.backgroundStart.opacity(0.38), Color(.systemBackground), palette.backgroundEnd.opacity(0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(palette.accentStart.opacity(0.24))
                .frame(width: 320, height: 320)
                .blur(radius: 34)
                .offset(x: 130, y: -280)

            Circle()
                .fill(palette.accentEnd.opacity(0.2))
                .frame(width: 260, height: 260)
                .blur(radius: 30)
                .offset(x: -140, y: 340)
        }
        .allowsHitTesting(false)
    }
}

extension Notification.Name {
    static let auraInAppBanner = Notification.Name("AuraInAppBanner")
    /// A push said another member changed shared data.
    static let auraRemoteChange = Notification.Name("AuraRemoteChange")
    /// APNs handed this device a (new) push token.
    static let auraPushTokenUpdated = Notification.Name("AuraPushTokenUpdated")
}

enum AuraMotion {
    static let quick   = Animation.easeInOut(duration: 0.18)
    static let smooth  = Animation.easeInOut(duration: 0.28)
    static let spring  = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let banner  = Animation.spring(response: 0.4, dampingFraction: 0.88)
}

enum AuraHaptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
