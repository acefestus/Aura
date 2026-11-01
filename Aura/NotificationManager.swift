import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

// MARK: - Notification Manager

class NotificationManager {
    static let shared = NotificationManager()

    enum ReminderKeys {
        static let eventId = "aura.eventId"
        static let title = "aura.title"
        static let body = "aura.body"
        static let soundRaw = "aura.soundRaw"
        static let colorHex = "aura.colorHex"
        static let icon = "aura.icon"
    }

    private enum ReminderActions {
        static let category = "AURA_EVENT_REMINDER"
        static let snooze = "AURA_SNOOZE"
    }

    private var reminderSnoozeMinutes: Int {
        let saved = UserDefaults.standard.integer(forKey: "reminderSnoozeMinutes")
        return saved == 0 ? 10 : saved
    }

    private var enableActionableReminders: Bool {
        UserDefaults.standard.object(forKey: "enableActionableReminders") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "enableActionableReminders")
    }

    private var enableReminderSnooze: Bool {
        UserDefaults.standard.object(forKey: "enableReminderSnooze") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "enableReminderSnooze")
    }

    private var enableSmartReminderMessaging: Bool {
        UserDefaults.standard.object(forKey: "enableSmartReminderMessaging") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "enableSmartReminderMessaging")
    }

    enum ReminderScheduleResult {
        case scheduled
        case skippedPastFireTime
        case notAuthorized
        case failed
    }

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
                self?.configureReminderCategories()
            }
    }

    /// Checks the current authorization status rather than blindly calling
    /// requestAuthorization every time -- that call only actually prompts
    /// once (on .notDetermined); after a denial it silently no-ops forever,
    /// which is how a reminder used to fail with zero feedback to the user.
    private func ensureAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func configureReminderCategories() {
        guard enableActionableReminders && enableReminderSnooze else {
            UNUserNotificationCenter.current().setNotificationCategories([])
            return
        }
        let snooze = UNNotificationAction(
            identifier: ReminderActions.snooze,
            title: "Snooze",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: ReminderActions.category,
            actions: [snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        guard response.actionIdentifier == ReminderActions.snooze else { return }
        let content = response.notification.request.content
        scheduleSnooze(from: content, minutes: reminderSnoozeMinutes)
    }

    @discardableResult
    func schedule(_ event: CalendarEvent, cat: EventCategory?) async -> ReminderScheduleResult {
        guard await ensureAuthorized() else {
            return .notAuthorized
        }
        configureReminderCategories()
        let c = UNMutableNotificationContent()
        c.title = event.title
        c.body = reminderBody(for: event, category: cat)
        if !event.location.isEmpty { c.subtitle = event.location }
        let appSound = event.soundOverride ?? cat?.sound ?? .systemDefault
        c.sound = appSound.unSound
        c.badge = 1
        if enableActionableReminders && enableReminderSnooze {
            c.categoryIdentifier = ReminderActions.category
        }
        c.userInfo = [
            ReminderKeys.eventId: event.id.uuidString,
            ReminderKeys.title: event.title,
            ReminderKeys.body: c.body,
            ReminderKeys.soundRaw: appSound.rawValue,
            ReminderKeys.colorHex: cat?.colorHex ?? "6366F1",
            ReminderKeys.icon: cat?.icon ?? "bell.fill"
        ]

        let fire: Date
        if event.isAllDay {
            fire = Calendar.current.startOfDay(for: event.startDate)
        } else {
            fire = event.startDate.addingTimeInterval(-(Double(event.alarmMins) * 60))
        }
        guard fire > Date() else {
            print("[Aurenda] Skipped scheduling reminder for '\(event.title)': fire time \(fire) is already in the past.")
            return .skippedPastFireTime
        }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let req   = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: c,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().add(req) { error in
                if let error {
                    print("[Aurenda] Failed to schedule reminder for '\(event.title)': \(error)")
                    continuation.resume(returning: .failed)
                } else {
                    continuation.resume(returning: .scheduled)
                }
            }
        }
    }

    func scheduleSnooze(from content: UNNotificationContent, minutes: Int) {
        guard minutes > 0 else { return }
        let snoozeContent = UNMutableNotificationContent()
        snoozeContent.title = content.userInfo[ReminderKeys.title] as? String ?? content.title
        snoozeContent.body = "Snoozed \(minutes)m \u{00B7} \(content.userInfo[ReminderKeys.body] as? String ?? content.body)"
        snoozeContent.subtitle = content.subtitle
        if let raw = content.userInfo[ReminderKeys.soundRaw] as? String,
           let appSound = AppSound(rawValue: raw) {
            snoozeContent.sound = appSound.unSound
        } else {
            snoozeContent.sound = content.sound
        }
        snoozeContent.badge = 1
        if enableActionableReminders && enableReminderSnooze {
            snoozeContent.categoryIdentifier = ReminderActions.category
        }
        snoozeContent.userInfo = content.userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes * 60), repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(UUID().uuidString)-snooze",
            content: snoozeContent,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func reminderBody(for event: CalendarEvent, category: EventCategory?) -> String {
        let fallback = category?.name ?? "Event"
        guard enableSmartReminderMessaging else { return fallback }

        if event.isAllDay {
            return "All-day reminder \u{00B7} \(fallback)"
        }

        if event.alarmMins > 0 {
            let startTime = event.startDate.formatted(date: .omitted, time: .shortened)
            return "Starts in \(event.alarmMins)m at \(startTime) \u{00B7} \(fallback)"
        }

        return "Starting now \u{00B7} \(fallback)"
    }

    func cancel(_ id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}
