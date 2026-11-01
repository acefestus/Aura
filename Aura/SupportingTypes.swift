import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

@MainActor
final class ShareManager: ObservableObject {
    @Published var pendingImport: AuraShareEnvelope? = nil

    func makeShareURL(senderName: String, permission: SharePermission, events: [CalendarEvent]) -> URL? {
        guard !events.isEmpty else { return nil }
        let envelope = AuraShareEnvelope(
            senderName: senderName,
            permission: permission,
            createdAt: Date(),
            events: events
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return nil }
        let payload = data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "aura://share?payload=\(payload)")
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "aura",
              url.host?.lowercased() == "share",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payload = comps.queryItems?.first(where: { $0.name == "payload" })?.value
        else { return }

        var b64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }

        guard let data = Data(base64Encoded: b64),
              let env = try? JSONDecoder().decode(AuraShareEnvelope.self, from: data)
        else { return }

        pendingImport = env
    }
}

struct Attachment: Codable, Identifiable {
    var id       = UUID()
    var filename: String
    var data:     Data
    var kind:     AttKind
    enum AttKind: String, Codable { case image, pdf, document, other }
}

enum Recurrence: String, Codable, CaseIterable {
    case none        = "Never"
    case daily       = "Every Day"
    case everyTwoDays = "Every 2 Days"
    case weekly      = "Every Week"
    case biweekly    = "Every 2 Weeks"
    case monthly     = "Every Month"
    case everyTwoMonths = "Every 2 Months"
    case quarterly   = "Every 3 Months"
    case yearly      = "Every Year"

    var icon: String {
        switch self {
        case .none:           return "slash.circle"
        case .daily:          return "sun.max.fill"
        case .everyTwoDays:   return "sun.and.horizon.fill"
        case .weekly:         return "calendar.badge.clock"
        case .biweekly:       return "calendar"
        case .monthly:        return "calendar.badge.checkmark"
        case .everyTwoMonths: return "arrow.2.squarepath"
        case .quarterly:      return "chart.bar.fill"
        case .yearly:         return "star.circle.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .none:           return "Does not repeat"
        case .daily:          return "Repeats every single day"
        case .everyTwoDays:   return "Repeats every 2 days"
        case .weekly:         return "Repeats once a week"
        case .biweekly:       return "Repeats every 2 weeks"
        case .monthly:        return "Repeats once a month"
        case .everyTwoMonths: return "Repeats every other month"
        case .quarterly:      return "Repeats 4× per year"
        case .yearly:         return "Repeats once a year"
        }
    }
}

// MARK: - Notification Sound

enum AppSound: String, Codable, CaseIterable {
    case systemDefault = "Default"
    case silent        = "Silent"
    case chime         = "Chime"
    case bell          = "Bell"
    case ding          = "Ding"
    case glass         = "Glass"
    case fanfare       = "Fanfare"
    case electronic    = "Electronic"
    case melody        = "Melody"
    case serenade      = "Serenade"
    case sunrise       = "Sunrise"
    case harmony       = "Harmony"
    case custom        = "Custom"

    /// The two groups shown in the picker -- short alert tones vs. the
    /// longer original melodies.
    static var tones:    [AppSound] { [.systemDefault, .silent, .chime, .bell, .ding, .glass, .fanfare, .electronic] }
    static var melodies: [AppSound] { [.melody, .serenade, .sunrise, .harmony] }

    var icon: String {
        switch self {
        case .silent:                    return "speaker.slash.fill"
        case .systemDefault:             return "speaker.wave.2.fill"
        case .chime, .bell, .ding:       return "bell.fill"
        case .glass:                     return "waveform"
        case .fanfare:                   return "music.note.list"
        case .electronic:                return "waveform.path"
        case .melody, .serenade, .sunrise, .harmony: return "music.note"
        case .custom:                    return "waveform.badge.plus"
        }
    }

    var unSound: UNNotificationSound? {
        switch self {
        case .silent:        return nil
        case .systemDefault: return .default
        case .custom:
            // A user-picked file lives in the app's Documents directory, not
            // the app bundle -- UNNotificationSound(named:) can only resolve
            // bundled files, so the *locked/backgrounded* system notification
            // always falls back to the default tone here. AlarmFiringManager
            // plays the real custom file directly for the foreground alarm.
            return .default
        default:
            return UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(rawValue).caf"))
        }
    }

    /// A short, one-shot player for auditioning a sound in the picker --
    /// distinct from AlarmFiringManager's looping alarm playback.
    func preview() {
        guard self != .silent else { return }
        let url: URL?
        if self == .custom {
            url = CustomSoundStore.fileURL
        } else if self == .systemDefault {
            url = Bundle.main.url(forResource: AppSound.chime.rawValue, withExtension: "caf")
        } else {
            url = Bundle.main.url(forResource: rawValue, withExtension: "caf")
        }
        guard let url else { return }
        SoundPreviewPlayer.shared.play(url: url)
    }
}

/// Keeps exactly one user-imported custom alarm sound (v1 scope: one global
/// file, not a per-event library) copied into the app's own sandbox so it
/// stays playable across launches without holding a security-scoped bookmark.
enum CustomSoundStore {
    private static let filenameKey = "aura.customSoundFilename"
    private static let displayNameKey = "aura.customSoundDisplayName"

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var fileURL: URL? {
        guard let filename = UserDefaults.standard.string(forKey: filenameKey) else { return nil }
        let url = documentsDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var hasCustomSound: Bool { fileURL != nil }

    static var displayName: String {
        UserDefaults.standard.string(forKey: displayNameKey) ?? "Custom Sound"
    }

    @discardableResult
    static func importSound(from sourceURL: URL) -> Bool {
        guard sourceURL.startAccessingSecurityScopedResource() else { return false }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        // Clear out any previously-imported file first (different extension
        // than last time would otherwise leave an orphaned copy behind).
        if let existing = fileURL { try? FileManager.default.removeItem(at: existing) }

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let filename = "custom-alarm-sound.\(ext)"
        let dest = documentsDirectory.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            UserDefaults.standard.set(filename, forKey: filenameKey)
            UserDefaults.standard.set(sourceURL.lastPathComponent, forKey: displayNameKey)
            return true
        } catch {
            print("[Aurenda] Couldn't import custom sound: \(error)")
            return false
        }
    }

    static func remove() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: filenameKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
    }
}

// MARK: - Share Extension Import Inbox
//
// AuraShareImport (the "Add to Aurenda" share extension) parses an .ics
// invite or a shared text snippet in its own sandboxed process and drops
// the result here via the shared App Group container -- it has no way to
// call into this app's EventStore directly. This struct's shape must stay
// in sync with the identically-named one duplicated in
// AuraShareImport/ShareViewController.swift.
struct AuraImportedEventDraft: Codable, Identifiable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var location: String = ""
    var startDate: Date
    var endDate: Date
    var sourceLabel: String = "Import"
}

enum SharedImportInbox {
    private static let key = "aura.pendingImportedEvents"
    private static var shared: UserDefaults { UserDefaults(suiteName: "group.com.personal.aura") ?? .standard }

    /// Reads and clears every draft waiting from the share extension.
    static func takeAll() -> [AuraImportedEventDraft] {
        defer { shared.removeObject(forKey: key) }
        guard let data = shared.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AuraImportedEventDraft].self, from: data)) ?? []
    }
}

/// One-shot playback for auditioning a sound in the picker, kept separate
/// from AlarmFiringManager's looping alarm player.
final class SoundPreviewPlayer {
    static let shared = SoundPreviewPlayer()
    private var player: AVAudioPlayer?

    func play(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.play()
            player = p
        } catch {
            print("[Aurenda] Couldn't preview sound: \(error)")
        }
    }
}

// MARK: - Default Categories

extension EventCategory {
    // A deliberately neutral starter set: it needs to make sense whether someone's
    // group is a family, a couple, roommates, a church small group, a travel crew,
    // or a study group -- and since categories are personal (shared across every
    // group a user belongs to, not duplicated per group), they can't assume any one
    // of those. No gendered family roles, no real organization/institution names.
    static let defaults: [EventCategory] = [
        .init(name: "Personal",       colorHex: "A78BFA", icon: "person.fill"),
        .init(name: "Work",           colorHex: "1F2937", icon: "briefcase.fill"),
        .init(name: "Appointment",    colorHex: "FF6B9D", icon: "heart.fill"),
        .init(name: "Meeting",        colorHex: "6366F1", icon: "person.3.sequence.fill"),
        .init(name: "Errand",         colorHex: "22C55E", icon: "cart.fill"),
        .init(name: "Class · Study",  colorHex: "06B6D4", icon: "book.fill"),
        .init(name: "Travel",         colorHex: "0EA5E9", icon: "airplane"),
        .init(name: "Health",         colorHex: "5DD39E", icon: "cross.case.fill"),
        .init(name: "Home · Chores",  colorHex: "D97706", icon: "house.fill"),
        .init(name: "Social",         colorHex: "EC4899", icon: "person.2.fill"),
        .init(name: "Celebration",    colorHex: "FF6347", icon: "gift.fill"),
        .init(name: "Finance",        colorHex: "475569", icon: "banknote.fill"),
    ]
}
