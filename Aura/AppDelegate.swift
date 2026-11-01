import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

// MARK: - Alarm Firing Manager
//
// Real alarm-like behavior is only possible while the app is in the
// foreground: a UNNotificationCenterDelegate's willPresent(_:) only fires
// then, and third-party apps have no entitlement to take over the Lock
// Screen the way the system Clock app can. So when a reminder's fire time
// arrives with Aurenda open, this suppresses the plain banner and instead
// loops a real sound + shows a full-screen alarm card until the user acts.
// When the app is backgrounded/locked, none of this runs -- iOS delivers
// the standard notification banner + one-shot sound instead, same as before.
final class AlarmFiringManager: ObservableObject {
    static let shared = AlarmFiringManager()

    struct FiringAlarm: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let categoryColor: Color
        let categoryIcon: String
        let content: UNNotificationContent
    }

    @Published var firing: FiringAlarm?
    private var player: AVAudioPlayer?

    func present(notification: UNNotification) {
        let content = notification.request.content
        let title = content.userInfo[NotificationManager.ReminderKeys.title] as? String ?? content.title
        let body = content.userInfo[NotificationManager.ReminderKeys.body] as? String ?? content.body
        let soundRaw = content.userInfo[NotificationManager.ReminderKeys.soundRaw] as? String
        let appSound = soundRaw.flatMap(AppSound.init(rawValue:)) ?? .systemDefault
        let colorHex = content.userInfo[NotificationManager.ReminderKeys.colorHex] as? String ?? "6366F1"
        let icon = content.userInfo[NotificationManager.ReminderKeys.icon] as? String ?? "bell.fill"

        firing = FiringAlarm(title: title, body: body, categoryColor: Color(hex: colorHex), categoryIcon: icon, content: content)
        playLoop(appSound)
        AuraHaptics.tap(.medium)
    }

    func dismiss() {
        stopLoop()
        firing = nil
    }

    func snooze(minutes: Int) {
        guard let content = firing?.content else { dismiss(); return }
        stopLoop()
        NotificationManager.shared.scheduleSnooze(from: content, minutes: minutes)
        firing = nil
    }

    private func playLoop(_ sound: AppSound) {
        stopLoop()
        guard sound != .silent else { return }
        let url: URL?
        if sound == .custom {
            // Falls through to Chime if the user picked Custom but never
            // actually imported a file (or it went missing).
            url = CustomSoundStore.fileURL ?? Bundle.main.url(forResource: AppSound.chime.rawValue, withExtension: "caf")
        } else if sound == .systemDefault {
            // .systemDefault has no bundle-accessible file to loop (it's a
            // private system asset), so it falls back to our own Chime tone
            // for the repeating alarm ring -- still respects Silent above.
            url = Bundle.main.url(forResource: AppSound.chime.rawValue, withExtension: "caf")
        } else {
            url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf")
        }
        guard let url else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.play()
            player = p
        } catch {
            print("[Aurenda] Couldn't loop alarm sound: \(error)")
        }
    }

    private func stopLoop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct AlarmFiringView: View {
    let alarm: AlarmFiringManager.FiringAlarm
    let onSnooze: () -> Void
    let onDismiss: () -> Void
    var snoozeMinutes: Int
    var snoozeEnabled: Bool

    @State private var pulse = false
    private var palette: AuraThemePalette { .current }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.backgroundStart, palette.backgroundEnd],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft, low-opacity glow in the category color -- a calm accent
            // rather than a full-bleed alert color, matching the app's other
            // hero surfaces (splash screen, group headers).
            Circle()
                .fill(alarm.categoryColor.opacity(0.30))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(y: -140)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image("AppIconGraphic")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text("Aurenda")
                        .auraFont(size: 15, weight: .semibold, design: .rounded)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 18)

                Spacer()

                ZStack {
                    Circle()
                        .fill(alarm.categoryColor.opacity(0.18))
                        .frame(width: 148, height: 148)
                        .scaleEffect(pulse ? 1.08 : 1.0)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 108, height: 108)
                    Image(systemName: alarm.categoryIcon)
                        .auraFont(size: 40, weight: .medium)
                        .foregroundStyle(alarm.categoryColor)
                }
                .onAppear { pulse = true }
                .padding(.bottom, 32)

                VStack(spacing: 8) {
                    Text(alarm.title)
                        .auraFont(size: 26, weight: .bold, design: .rounded)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(alarm.body)
                        .auraFont(size: 15, weight: .medium)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()
                Spacer()

                VStack(spacing: 12) {
                    if snoozeEnabled {
                        Button(action: onSnooze) {
                            Text("Snooze \(snoozeMinutes)m")
                                .auraFont(size: 16, weight: .semibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.md, style: .continuous)
                                        .stroke(.white.opacity(0.18), lineWidth: AuraDesignTokens.Stroke.subtle)
                                )
                        }
                    }
                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .auraFont(size: 16, weight: .semibold)
                            .foregroundStyle(palette.backgroundStart)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.md, style: .continuous))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - App Delegate  (shows banner even when app is open)
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.shared.configureReminderCategories()
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "aura.apnsToken")
        NotificationCenter.default.post(name: .auraPushTokenUpdated, object: nil)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Aurenda] Push registration failed: \(error.localizedDescription)")
    }

    private func isGroupPush(_ notification: UNNotification) -> Bool {
        notification.request.trigger is UNPushNotificationTrigger
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Another member's change, not a reminder: a normal banner, and pull it in.
        if isGroupPush(notification) {
            NotificationCenter.default.post(name: .auraRemoteChange, object: nil)
            completionHandler([.banner, .list, .sound])
            return
        }

        let enabled = UserDefaults.standard.object(forKey: "enableInAppBanner") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "enableInAppBanner")

        guard enabled else {
            completionHandler([.banner, .list, .sound, .badge])
            return
        }

        // The app is in the foreground right now -- this is the one moment a
        // third-party app can show something more than a banner, so a real
        // full-screen alarm card takes over instead (with its own looping
        // sound), and the plain system banner/one-shot sound are suppressed
        // to avoid overlapping with it. Locked/backgrounded delivery never
        // reaches this delegate method, so it still falls through to the
        // standard notification banner + sound exactly as before.
        DispatchQueue.main.async {
            AlarmFiringManager.shared.present(notification: notification)
        }
        completionHandler([.list, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if isGroupPush(response.notification) {
            NotificationCenter.default.post(name: .auraRemoteChange, object: nil)
        } else {
            NotificationManager.shared.handleNotificationResponse(response)
        }
        completionHandler()
    }
}
