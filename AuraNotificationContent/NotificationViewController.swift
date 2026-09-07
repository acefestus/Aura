import UIKit
import UserNotifications
import UserNotificationsUI
import SwiftUI

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: UInt64
        switch h.count {
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (255, 255, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}

struct ReminderThemePalette {
    var backgroundStartHex = "08111F"
    var backgroundEndHex = "1B2A41"
    var accentStartHex = "0EA5A4"
    var accentEndHex = "F59E0B"

    var backgroundStart: Color { Color(hex: backgroundStartHex) }
    var backgroundEnd: Color { Color(hex: backgroundEndHex) }
    var accentStart: Color { Color(hex: accentStartHex) }
    var accentEnd: Color { Color(hex: accentEndHex) }

    private struct StoredTheme: Decodable {
        let c1, c2, n1, n2: String
    }

    static var current: ReminderThemePalette {
        guard let json = UserDefaults(suiteName: "group.com.personal.aura")?.string(forKey: "widgetThemeJSON"),
              let data = json.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredTheme.self, from: data) else {
            return ReminderThemePalette()
        }
        return ReminderThemePalette(
            backgroundStartHex: stored.c1,
            backgroundEndHex: stored.c2,
            accentStartHex: stored.n1,
            accentEndHex: stored.n2
        )
    }
}

struct ReminderCardView: View {
    let title: String
    let subtitle: String
    let message: String
    let dateLabel: String

    @ViewBuilder
    var cardBody: some View {
        let palette = ReminderThemePalette.current
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [palette.backgroundStart, palette.backgroundEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.accentStart.opacity(0.32))
                .frame(width: 180, height: 180)
                .blur(radius: 40)
                .offset(x: -60, y: -60)
            Circle()
                .fill(palette.accentEnd.opacity(0.26))
                .frame(width: 160, height: 160)
                .blur(radius: 40)
                .offset(x: 140, y: 90)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient(colors: [palette.accentStart, palette.accentEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 22)
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("AURENDA")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                }

                Text(title)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }

                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !dateLabel.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .bold))
                        Text(dateLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.16), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
                }
            }
            .padding(16)
        }
    }

    var body: some View { cardBody }
}

class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var hostingController: UIHostingController<ReminderCardView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let card = ReminderCardView(title: "", subtitle: "", message: "", dateLabel: "")
        let hosting = UIHostingController(rootView: card)
        hostingController = hosting
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d · h:mm a"
        let dateLabel = df.string(from: notification.date)

        let card = ReminderCardView(
            title: content.title,
            subtitle: content.subtitle,
            message: content.body,
            dateLabel: dateLabel
        )
        hostingController?.rootView = card
        preferredContentSize = CGSize(width: view.bounds.width, height: 190)
    }
}
