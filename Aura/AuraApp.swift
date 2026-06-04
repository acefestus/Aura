// ============================================================
//  Aura — Premium Calendar & Reminder App
//  Single-file SwiftUI implementation
//  Minimum: iOS 16  |  No third-party dependencies
//  Sideload via AltStore, Sideloadly, or direct Xcode install
// ============================================================

import SwiftUI
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import CloudKit
import HealthKit

// MARK: - App Entry

@main
struct AuraApp: App {
    @StateObject private var store = EventStore()
    @StateObject private var shareManager = ShareManager()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AuraAppShellView()
                .environmentObject(store)
                .environmentObject(shareManager)
                .onAppear { NotificationManager.shared.requestPermission() }
                .onOpenURL { url in
                    shareManager.handleIncomingURL(url)
                }
        }
    }
}

struct AuraAppShellView: View {
    @EnvironmentObject var store: EventStore
    @AppStorage("aura.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("aura.allowOfflineMode") private var allowOfflineMode = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                AuraSplashScreen()
                    .transition(.opacity)
            } else if !hasSeenOnboarding {
                AuraOnboardingView {
                    hasSeenOnboarding = true
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !store.hasServerSession && !allowOfflineMode {
                AuraAuthGatewayView()
                    .transition(.opacity)
            } else {
                ContentView()
                    .transition(.opacity)
            }
        }
        .animation(AuraMotion.smooth, value: showSplash)
        .task {
            guard showSplash else { return }
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(AuraMotion.smooth) {
                showSplash = false
            }
        }
    }
}

struct AuraSplashScreen: View {
    var body: some View {
        let p = AuraThemePalette.current
        ZStack {
            LinearGradient(colors: [p.backgroundStart, p.backgroundEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                Text("Aura")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Family Life, Beautifully Orchestrated")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }
}

private struct AuraHeroFamilyImage: View {
    let assetName: String
    let fallbackIcon: String

    var body: some View {
        Group {
            if let image = UIImage(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(hex: "1E293B"), Color(hex: "0F172A")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

struct AuraOnboardingView: View {
    @AppStorage("aura.allowOfflineMode") private var allowOfflineMode = false
    @State private var page = 0
    var onFinish: () -> Void

    var body: some View {
        let p = AuraThemePalette.current
        ZStack {
            LinearGradient(colors: [p.backgroundStart.opacity(0.95), p.backgroundEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                TabView(selection: $page) {
                    onboardingCard(
                        title: "Built For Your Family",
                        subtitle: "Events, lists, routines, and memories in one premium daily hub.",
                        imageAsset: "family_all",
                        fallbackIcon: "person.3.sequence.fill"
                    ).tag(0)

                    onboardingCard(
                        title: "Private By Design",
                        subtitle: "Choose Personal, Family, or Custom visibility for every activity.",
                        imageAsset: "family_mom",
                        fallbackIcon: "lock.shield.fill"
                    ).tag(1)

                    onboardingCard(
                        title: "Real-Time Household Sync",
                        subtitle: "Stay in sync across phones with your Aura account and household.",
                        imageAsset: "family_kid",
                        fallbackIcon: "arrow.triangle.2.circlepath"
                    ).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxHeight: 520)

                HStack(spacing: 10) {
                    Button(page == 2 ? "Start Setup" : "Next") {
                        AuraHaptics.tap(.medium)
                        if page == 2 {
                            allowOfflineMode = false
                            onFinish()
                        } else {
                            withAnimation(AuraMotion.smooth) { page += 1 }
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Skip for now") {
                        allowOfflineMode = true
                        onFinish()
                    }
                    .buttonStyle(.bordered)
                }
                .tint(.white)
                .foregroundColor(.black)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
    }

    private func onboardingCard(title: String, subtitle: String, imageAsset: String, fallbackIcon: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AuraHeroFamilyImage(assetName: imageAsset, fallbackIcon: fallbackIcon)
                .frame(height: 360)
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.86))
        }
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}

struct AuraAuthGatewayView: View {
    enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case create = "Create Account"
    }

    @EnvironmentObject var store: EventStore
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @AppStorage("backendAccountEmail") private var backendAccountEmail = ""
    @AppStorage("profileDisplayName") private var profileDisplayName = ""
    @AppStorage("aura.allowOfflineMode") private var allowOfflineMode = false
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var householdName = "Our Family"
    @State private var householdCode = ""
    @State private var message = ""
    @State private var isWorking = false

    var body: some View {
        let p = AuraThemePalette.current
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Aura")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text("Set up your family account first for the full premium sync experience.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    AuraHeroFamilyImage(assetName: "family_dad", fallbackIcon: "person.fill")
                    AuraHeroFamilyImage(assetName: "family_mom", fallbackIcon: "person.fill")
                    AuraHeroFamilyImage(assetName: "family_kid", fallbackIcon: "figure.2.and.child.holdinghands")
                }
                .frame(height: 160)

                VStack(spacing: 12) {
                    TextField("Backend URL", text: Binding(
                        get: { backendBaseURL },
                        set: {
                            backendBaseURL = $0
                            store.updateBackendBaseURL($0)
                        }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)

                    if mode == .create {
                        TextField("Display name", text: $displayName)
                    }

                    Button {
                        isWorking = true
                        message = ""
                        Task {
                            let result: Result<Void, Error>
                            if mode == .create {
                                result = await store.registerServerAccount(email: email, password: password, displayName: displayName)
                            } else {
                                result = await store.loginServerAccount(email: email, password: password)
                            }
                            await MainActor.run {
                                isWorking = false
                                switch result {
                                case .success:
                                    password = ""
                                    backendAccountEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        profileDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                    message = mode == .create ? "Account created. Continue with household setup." : "Signed in successfully."
                                case .failure(let error):
                                    message = error.localizedDescription
                                }
                            }
                        }
                    } label: {
                        Label(mode == .create ? "Create Account" : "Sign In", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || (mode == .create && displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                    if store.hasServerSession {
                        Divider().padding(.vertical, 6)

                        TextField("Household name", text: $householdName)
                        Button {
                            isWorking = true
                            message = ""
                            Task {
                                let result = await store.createServerHousehold(name: householdName)
                                await MainActor.run {
                                    isWorking = false
                                    switch result {
                                    case .success(let code):
                                        householdCode = code
                                        message = "Household created. Code: \(code)"
                                    case .failure(let error):
                                        message = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Label("Create Household", systemImage: "person.3.sequence.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        TextField("Join code", text: $householdCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        Button {
                            isWorking = true
                            message = ""
                            Task {
                                let result = await store.joinServerHousehold(code: householdCode)
                                await MainActor.run {
                                    isWorking = false
                                    switch result {
                                    case .success:
                                        message = "Joined household successfully."
                                    case .failure(let error):
                                        message = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Label("Join Household", systemImage: "person.2.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(householdCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            allowOfflineMode = true
                            message = "You can continue offline and set up account later in Settings."
                        } label: {
                            Text("Continue Offline")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }

                    if isWorking { ProgressView() }
                    if !message.isEmpty {
                        Text(message)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(LinearGradient(colors: [Color.white, Color.white.opacity(0.96)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(p.accentStart.opacity(0.22), lineWidth: 1))
            }
            .padding(20)
        }
        .background(
            LinearGradient(colors: [p.backgroundStart.opacity(0.2), p.backgroundEnd.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        .onAppear {
            email = backendAccountEmail
            displayName = profileDisplayName
            store.updateBackendBaseURL(backendBaseURL)
        }
    }
}

// MARK: - App Delegate  (shows banner even when app is open)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        let enabled = UserDefaults.standard.object(forKey: "enableInAppBanner") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "enableInAppBanner")

        if enabled {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .auraInAppBanner,
                    object: nil,
                    userInfo: [
                        "title": content.title,
                        "message": content.body
                    ]
                )
            }
        }
        completionHandler([.sound, .badge])
    }
}

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
        backgroundStartHex: "1E1B4B",
        backgroundEndHex: "4C1D95",
        accentStartHex: "6366F1",
        accentEndHex: "A78BFA"
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

extension Notification.Name {
    static let auraInAppBanner = Notification.Name("AuraInAppBanner")
}

enum AuraMotion {
    static let quick   = Animation.easeInOut(duration: 0.16)
    static let smooth  = Animation.easeInOut(duration: 0.24)
    static let spring  = Animation.spring(response: 0.34, dampingFraction: 0.88)
    static let banner  = Animation.spring(response: 0.35, dampingFraction: 0.9)
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

// MARK: - Models

struct EventCategory: Identifiable, Codable, Equatable, Hashable {
    var id         = UUID()
    var name:      String
    var colorHex:  String
    var icon:      String
    var parentId:  UUID?     = nil
    var isCustom:  Bool      = false
    var sound:     AppSound? = nil   // nil = system default

    var color: Color { Color(hex: colorHex) }
    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct CalendarEvent: Identifiable, Codable, Equatable {
    var id               = UUID()
    var title:           String
    var notes:           String       = ""
    var startDate:       Date
    var endDate:         Date
    var isAllDay:        Bool         = false
    var categoryId:      UUID
    var location:        String       = ""
    var alarmMins:       Int          = 15
    var hasAlarm:        Bool         = true
    var url:             String       = ""
    var attachments:     [Attachment] = []
    var recurrence:      Recurrence   = .none
    var soundOverride:   AppSound?    = nil   // nil = use category sound
    var sharedBy:        String?      = nil
    var sharePermission: SharePermission = .edit
    var ownerName:       String       = ""
    var visibility:      VisibilityScope = .family
    var sharedWithNames: [String]     = []
    var assignedMemberIds: [UUID]     = []

    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
}

enum SharePermission: String, Codable, CaseIterable {
    case view = "View"
    case edit = "Edit"

    var subtitle: String {
        switch self {
        case .view: return "Receiver can view only"
        case .edit: return "Receiver can edit this event"
        }
    }
}

struct AuraShareEnvelope: Codable {
    var senderName: String
    var permission: SharePermission
    var createdAt: Date
    var events: [CalendarEvent]
}

enum SharedActivityAction: String, Codable, CaseIterable {
    case accepted = "Accepted"
    case permissionChanged = "Permission Changed"
    case revoked = "Revoked"
}

struct SharedActivityEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp: Date
    var sender: String
    var eventTitle: String
    var action: SharedActivityAction
    var details: String
}

struct FamilyMember: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var colorHex: String
    var role: String
    var allowsStepSharing: Bool = false

    var color: Color { Color(hex: colorHex) }
}

enum ShoppingStore: String, Codable, CaseIterable {
    case rewe = "Rewe"
    case aldi = "Aldi"
    case edeka = "Edeka"
    case lidl = "Lidl"
    case dm = "DM"
    case afroStore = "Afro Store"
    case online = "Online"
    case turkishStore = "Turkish Store"
    case others = "Others"

    var icon: String {
        switch self {
        case .rewe, .aldi, .edeka, .lidl, .dm, .afroStore, .turkishStore, .others:
            return "basket.fill"
        case .online:
            return "shippingbox.fill"
        }
    }
}

enum VisibilityScope: String, Codable, CaseIterable {
    case personal = "Personal"
    case family = "Family"
    case custom = "Custom"

    var icon: String {
        switch self {
        case .personal: return "person.fill"
        case .family: return "person.3.fill"
        case .custom: return "person.2.badge.gearshape.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .personal: return "Only you can see this"
        case .family: return "Visible to the whole household"
        case .custom: return "Visible to selected family members"
        }
    }
}

enum FamilyActivityKind: String, Codable, CaseIterable {
    case walk = "Walk"
    case run = "Run"
    case play = "Play"
    case sport = "Sport"
    case school = "School"
    case church = "Church"
    case other = "Other"

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .play: return "gamecontroller.fill"
        case .sport: return "figure.soccer"
        case .school: return "book.closed.fill"
        case .church: return "building.columns.fill"
        case .other: return "sparkles"
        }
    }
}

struct FamilyActivity: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: FamilyActivityKind
    var date: Date
    var durationMinutes: Int
    var notes: String
    var participantIds: [UUID]
    var ownerName: String = ""
    var visibility: VisibilityScope = .family
    var sharedWithNames: [String] = []
}

enum FamilyListKind: String, Codable, CaseIterable {
    case supermarket = "Supermarket"
    case pharmacy = "Pharmacy"
    case chores = "Chores"
    case pantry = "Pantry"
    case meals = "Meals"
    case other = "Other"

    var icon: String {
        switch self {
        case .supermarket: return "cart.fill"
        case .pharmacy: return "cross.case.fill"
        case .chores: return "checklist"
        case .pantry: return "shippingbox.fill"
        case .meals: return "fork.knife"
        case .other: return "list.bullet"
        }
    }
}

struct FamilyListItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var quantity: String
    var note: String
    var isDone: Bool
    var assignedMemberId: UUID?
    var preferredStore: ShoppingStore? = nil
    var dueDate: Date? = nil
    var completedByName: String? = nil
    var boughtAt: Date? = nil
}

struct FamilyList: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var kind: FamilyListKind
    var createdAt: Date
    var items: [FamilyListItem]
    var ownerName: String = ""
    var visibility: VisibilityScope = .family
    var sharedWithNames: [String] = []
}

struct FamilyStepSnapshot: Identifiable, Codable, Equatable {
    var id = UUID()
    var ownerName: String
    var date: Date
    var steps: Int
    var visibility: VisibilityScope = .personal
    var sharedWithNames: [String] = []
    var updatedAt: Date = Date()
}

struct LiveFamilyActivitySession: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: FamilyActivityKind
    var startedAt: Date
    var notes: String
    var participantIds: [UUID]
    var ownerName: String
    var visibility: VisibilityScope
    var sharedWithNames: [String]
}

struct HouseholdSyncPayload: Codable {
    var updatedAt: Date
    var updatedBy: String
    var categories: [EventCategory]
    var events: [CalendarEvent]
    var members: [FamilyMember]
    var familyLists: [FamilyList]
    var familyActivities: [FamilyActivity]
    var stepSnapshots: [FamilyStepSnapshot]
}

struct AuraRemoteUser: Codable {
    var id: String
    var email: String
    var displayName: String
}

struct AuraRemoteMembership: Codable {
    var userId: String
    var householdId: String
    var role: String
    var joinedAt: String
}

struct AuraRemoteHousehold: Codable {
    var id: String
    var name: String
    var code: String
    var createdBy: String
    var createdAt: String
}

struct AuraRemoteAuthResponse: Codable {
    var token: String
    var user: AuraRemoteUser
}

struct AuraRemoteMeResponse: Codable {
    var user: AuraRemoteUser
    var membership: AuraRemoteMembership?
}

struct AuraRemoteCurrentHouseholdResponse: Codable {
    var household: AuraRemoteHousehold?
    var membership: AuraRemoteMembership?
}

struct AuraRemoteCreateHouseholdResponse: Codable {
    var householdId: String
    var code: String
    var membership: AuraRemoteMembership
}

struct AuraRemoteJoinHouseholdResponse: Codable {
    var household: AuraRemoteHousehold
    var membership: AuraRemoteMembership
}

struct AuraRemoteSnapshotRecord: Codable {
    var householdId: String
    var updatedAt: Date
    var updatedBy: String
    var payload: HouseholdSyncPayload
}

struct AuraRemoteSnapshotEnvelope: Codable {
    var snapshot: AuraRemoteSnapshotRecord?
}

struct AuraRemoteUserEnvelope: Codable {
    var user: AuraRemoteUser
}

struct AuraRemoteOkEnvelope: Codable {
    var ok: Bool
}

enum AuraServerError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case unauthorized
    case networkUnavailable
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Enter a valid backend URL first."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .networkUnavailable:
            return "Network unavailable. Check your connection and try again."
        case .requestFailed(let message):
            return message
        }
    }
}

final class StepTrackingManager {
    static let shared = StepTrackingManager()
    private let healthStore = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable,
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: [stepsType]) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    func fetchTodaySteps() async -> Int? {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let steps = stats?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: Int(steps))
            }
            healthStore.execute(query)
        }
    }
}

actor HouseholdSyncEngine {
    static let shared = HouseholdSyncEngine()

    private let container = CKContainer.default()
    private var db: CKDatabase { container.publicCloudDatabase }

    private func recordId(for householdCode: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "household-\(householdCode.lowercased())")
    }

    func upload(householdCode: String, payload: HouseholdSyncPayload) async throws {
        let rid = recordId(for: householdCode)
        let rec: CKRecord
        do {
            rec = try await db.record(for: rid)
        } catch {
            rec = CKRecord(recordType: "AuraHousehold", recordID: rid)
        }
        rec["payload"] = String(data: try JSONEncoder().encode(payload), encoding: .utf8) as CKRecordValue?
        rec["updatedAt"] = payload.updatedAt as CKRecordValue
        rec["updatedBy"] = payload.updatedBy as CKRecordValue
        _ = try await db.save(rec)
    }

    func download(householdCode: String) async throws -> HouseholdSyncPayload? {
        let rid = recordId(for: householdCode)
        do {
            let rec = try await db.record(for: rid)
            guard let raw = rec["payload"] as? String,
                  let d = raw.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(HouseholdSyncPayload.self, from: d)
            else { return nil }
            return payload
        } catch {
            return nil
        }
    }
}

actor AuraServerSyncEngine {
    static let shared = AuraServerSyncEngine()

    private func normalizedBaseURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AuraServerError.invalidBaseURL }
        let candidate = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate) else { throw AuraServerError.invalidBaseURL }
        return url
    }

    private func request<Response: Decodable>(
        baseURL: String,
        path: String,
        method: String = "GET",
        token: String? = nil,
        body: Data? = nil
    ) async throws -> Response {
        let base = try normalizedBaseURL(baseURL)
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = base.appending(path: cleanPath)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            if let netErr = error as? URLError,
               netErr.code == .notConnectedToInternet || netErr.code == .networkConnectionLost || netErr.code == .timedOut {
                throw AuraServerError.networkUnavailable
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuraServerError.invalidResponse
        }
        if http.statusCode == 401 {
            throw AuraServerError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuraServerError.requestFailed(serverErrorMessage(from: data, statusCode: http.statusCode))
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AuraServerError.invalidResponse
        }
    }

    private func request<Body: Encodable, Response: Decodable>(
        baseURL: String,
        path: String,
        method: String,
        token: String? = nil,
        payload: Body
    ) async throws -> Response {
        let data = try JSONEncoder().encode(payload)
        return try await request(baseURL: baseURL, path: path, method: method, token: token, body: data)
    }

    private func serverErrorMessage(from data: Data, statusCode: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] {
            if let string = message as? String {
                return string
            }
            if let payload = try? JSONSerialization.data(withJSONObject: message),
               let string = String(data: payload, encoding: .utf8) {
                return string
            }
        }
        if let fallback = String(data: data, encoding: .utf8), !fallback.isEmpty {
            return fallback
        }
        return "Request failed with status \(statusCode)."
    }

    func register(baseURL: String, email: String, password: String, displayName: String) async throws -> AuraRemoteAuthResponse {
        try await request(
            baseURL: baseURL,
            path: "/auth/register",
            method: "POST",
            payload: ["email": email, "password": password, "displayName": displayName]
        )
    }

    func login(baseURL: String, email: String, password: String) async throws -> AuraRemoteAuthResponse {
        try await request(
            baseURL: baseURL,
            path: "/auth/login",
            method: "POST",
            payload: ["email": email, "password": password]
        )
    }

    func me(baseURL: String, token: String) async throws -> AuraRemoteMeResponse {
        try await request(baseURL: baseURL, path: "/me", token: token)
    }

    func currentHousehold(baseURL: String, token: String) async throws -> AuraRemoteCurrentHouseholdResponse {
        try await request(baseURL: baseURL, path: "/households/current", token: token)
    }

    func createHousehold(baseURL: String, token: String, name: String) async throws -> AuraRemoteCreateHouseholdResponse {
        try await request(
            baseURL: baseURL,
            path: "/households",
            method: "POST",
            token: token,
            payload: ["name": name]
        )
    }

    func joinHousehold(baseURL: String, token: String, code: String) async throws -> AuraRemoteJoinHouseholdResponse {
        try await request(
            baseURL: baseURL,
            path: "/households/join",
            method: "POST",
            token: token,
            payload: ["code": code]
        )
    }

    func uploadSnapshot(baseURL: String, token: String, payload: HouseholdSyncPayload) async throws -> AuraRemoteSnapshotEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/sync/snapshot",
            method: "PUT",
            token: token,
            payload: ["payload": payload]
        )
    }

    func downloadSnapshot(baseURL: String, token: String) async throws -> HouseholdSyncPayload? {
        let response: AuraRemoteSnapshotEnvelope = try await request(baseURL: baseURL, path: "/sync/snapshot", token: token)
        return response.snapshot?.payload
    }

    func updateProfile(baseURL: String, token: String, displayName: String) async throws -> AuraRemoteUserEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/me/profile",
            method: "PATCH",
            token: token,
            payload: ["displayName": displayName]
        )
    }

    func changePassword(baseURL: String, token: String, currentPassword: String, newPassword: String) async throws -> AuraRemoteOkEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/me/password",
            method: "PATCH",
            token: token,
            payload: ["currentPassword": currentPassword, "newPassword": newPassword]
        )
    }
}

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

    var icon: String {
        switch self {
        case .silent:                    return "speaker.slash.fill"
        case .systemDefault:             return "speaker.wave.2.fill"
        case .chime, .bell, .ding:       return "bell.fill"
        case .glass:                     return "waveform"
        case .fanfare:                   return "music.note.list"
        case .electronic:                return "waveform.path"
        }
    }

    var unSound: UNNotificationSound? {
        switch self {
        case .silent:        return nil
        case .systemDefault: return .default
        default:
            return UNNotificationSound(named: UNNotificationSoundName(rawValue))
        }
    }
}

// MARK: - Default Categories

extension EventCategory {
    static let defaults: [EventCategory] = [
        // Doctors
        .init(name: "Doctor · Mama",       colorHex: "FF6B9D", icon: "heart.fill"),
        .init(name: "Doctor · Papa",        colorHex: "4A90D9", icon: "heart.fill"),
        .init(name: "Doctor · Children",    colorHex: "5DD39E", icon: "heart.fill"),
        // Meetings
        .init(name: "Meeting · Work",       colorHex: "8B5CF6", icon: "person.3.fill"),
        .init(name: "Meeting · Personal",   colorHex: "A78BFA", icon: "person.2.fill"),
        .init(name: "Meeting · Team",       colorHex: "6366F1", icon: "person.3.sequence.fill"),
        // Life
        .init(name: "Holiday",              colorHex: "F59E0B", icon: "sun.max.fill"),
        .init(name: "Job Interview",        colorHex: "14B8A6", icon: "briefcase.fill"),
        .init(name: "Class",                colorHex: "06B6D4", icon: "book.fill"),
        .init(name: "Kindergarten",         colorHex: "22C55E", icon: "figure.and.child.holdinghands"),
        .init(name: "Family",               colorHex: "F97316", icon: "house.heart.fill"),
        .init(name: "Work",                 colorHex: "1F2937", icon: "briefcase.fill"),
        .init(name: "Nuvisan",              colorHex: "0EA5E9", icon: "building.2.fill"),
        // Choir
        .init(name: "Choir · Church",       colorHex: "7C3AED", icon: "music.note"),
        .init(name: "Choir · One Sound",    colorHex: "EC4899", icon: "music.mic"),
        .init(name: "Choir · New Wine",     colorHex: "9F1239", icon: "music.note.list"),
        // More
        .init(name: "Sunday Service",       colorHex: "D97706", icon: "book.closed.fill"),
        .init(name: "Job",                  colorHex: "475569", icon: "briefcase"),
        .init(name: "Birthday",             colorHex: "FF6347", icon: "gift.fill"),
    ]
}

// MARK: - Event Store

class EventStore: ObservableObject {
    @Published var events:     [CalendarEvent] = []
    @Published var categories: [EventCategory] = []
    @Published var sharedActivity: [SharedActivityEntry] = []
    @Published var members: [FamilyMember] = []
    @Published var familyLists: [FamilyList] = []
    @Published var familyActivities: [FamilyActivity] = []
    @Published var familyStepSnapshots: [FamilyStepSnapshot] = []
    @Published var activeActivitySession: LiveFamilyActivitySession? = nil
    @Published var isBootstrapping = true
    @Published var syncStatus = "Sync disabled"
    @Published var serverAccountEmail = ""
    @Published var serverHouseholdName = ""
    @AppStorage("colorScheme") var scheme: String = "system"
    @AppStorage("profileDisplayName") private var profileDisplayName = ""
    @AppStorage("activeFamilyMemberId") private var activeFamilyMemberId = ""
    @AppStorage("householdCode") private var householdCode = ""
    @AppStorage("householdLastSnapshot") private var householdLastSnapshot = 0.0
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @AppStorage("backendAuthToken") private var backendAuthToken = ""
    @AppStorage("backendAccountEmail") private var backendAccountEmail = ""
    @AppStorage("backendHouseholdId") private var backendHouseholdId = ""
    @AppStorage("backendHouseholdName") private var backendStoredHouseholdName = ""
    @AppStorage("viewAsMemberName") private var viewAsMemberName = ""
    @AppStorage("shareDailySteps") private var shareDailySteps = false
    @AppStorage("dailyStepVisibility") private var dailyStepVisibilityRaw = VisibilityScope.personal.rawValue
    @AppStorage("dailyStepSharedWithNames") private var dailyStepSharedWithNamesRaw = ""

    private let eKey = "aura.events"
    private let cKey = "aura.categories"
    private let aKey = "aura.sharedActivity"
    private let mKey = "aura.familyMembers"
    private let lKey = "aura.familyLists"
    private let fKey = "aura.familyActivities"
    private let sKey = "aura.familyStepSnapshots"
    private let liveActivityKey = "aura.liveFamilyActivity"
    private var shared: UserDefaults { UserDefaults(suiteName: "group.com.personal.aura") ?? .standard }
    private var syncDebounceTask: Task<Void, Never>? = nil
    private var periodicPullTask: Task<Void, Never>? = nil
    private var applyingRemoteSnapshot = false

    var activeProfileName: String {
        if let activeMember {
            return activeMember.name
        }
        let clean = profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Aura User" : clean
    }

    var activeMember: FamilyMember? {
        guard let id = UUID(uuidString: activeFamilyMemberId) else { return nil }
        return members.first(where: { $0.id == id })
    }

    var currentViewerName: String {
        let clean = viewAsMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? activeProfileName : clean
    }

    var dailyStepVisibility: VisibilityScope {
        VisibilityScope(rawValue: dailyStepVisibilityRaw) ?? .personal
    }

    var dailyStepSharedWithNames: [String] {
        dailyStepSharedWithNamesRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var currentHouseholdCode: String {
        householdCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentBackendBaseURL: String {
        backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasServerSession: Bool {
        !currentBackendBaseURL.isEmpty && !backendAuthToken.isEmpty
    }

    var hasServerHousehold: Bool {
        hasServerSession && !backendHouseholdId.isEmpty
    }

    var currentSyncBackendLabel: String {
        if hasServerHousehold {
            return "Aura Server"
        }
        if !currentHouseholdCode.isEmpty {
            return "CloudKit"
        }
        return "Local only"
    }

    init() {
        loadCats()
        loadEvents()
        loadSharedActivity()
        loadMembers()
        loadFamilyLists()
        loadFamilyActivities()
        loadFamilyStepSnapshots()
        loadLiveActivitySession()
        serverAccountEmail = backendAccountEmail
        serverHouseholdName = backendStoredHouseholdName
        if hasServerSession {
            Task { @MainActor [weak self] in
                await self?.refreshServerContext()
            }
        }
        startPeriodicPull()
        queueSyncPush()
        refreshDailyStepsIfEnabled()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            withAnimation(AuraMotion.smooth) {
                self.isBootstrapping = false
            }
        }
    }

    // ── Categories ──────────────────────────────────────────
    func loadCats() {
        if let d = shared.data(forKey: cKey),
           let v = try? JSONDecoder().decode([EventCategory].self, from: d) {
            categories = v
            var changed = false
            for i in categories.indices {
                if categories[i].name == "Birthday 🎂" {
                    categories[i].name = "Birthday"
                    changed = true
                }
                if categories[i].name == "Sunday Service", categories[i].icon == "star.fill" {
                    categories[i].icon = "book.closed.fill"
                    changed = true
                }
            }
            let existingNames = Set(categories.map { $0.name.lowercased() })
            let missingDefaults = EventCategory.defaults.filter { !existingNames.contains($0.name.lowercased()) }
            if !missingDefaults.isEmpty {
                categories.append(contentsOf: missingDefaults)
                changed = true
            }
            if changed {
                saveCats()
            }
        } else {
            categories = EventCategory.defaults
            saveCats()
        }
    }
    func saveCats() {
        if let d = try? JSONEncoder().encode(categories) {
            shared.set(d, forKey: cKey)
        }
        if !applyingRemoteSnapshot { queueSyncPush() }
    }
    func addCategory(_ c: EventCategory) { categories.append(c); saveCats() }
    func updateCategory(_ c: EventCategory) {
        guard let i = categories.firstIndex(where: { $0.id == c.id }) else { return }
        categories[i] = c
        saveCats()
    }
    func deleteCategory(id: UUID) {
        guard categories.count > 1 else { return }
        guard let replacement = categories.first(where: { $0.id != id })?.id else { return }

        for i in events.indices where events[i].categoryId == id {
            events[i].categoryId = replacement
        }
        categories.removeAll { $0.id == id }
        saveCats()
        saveEvents()
    }
    func category(for id: UUID) -> EventCategory? { categories.first { $0.id == id } }

    // ── Events ───────────────────────────────────────────────
    func loadEvents() {
        if let d = shared.data(forKey: eKey),
           let v = try? JSONDecoder().decode([CalendarEvent].self, from: d) {
            events = v
        }
    }
    func saveEvents() {
        if let d = try? JSONEncoder().encode(events) {
            shared.set(d, forKey: eKey)
        }
        if !applyingRemoteSnapshot { queueSyncPush() }
    }
    func addEvent(_ e: CalendarEvent) {
        events.append(e)
        events.sort { $0.startDate < $1.startDate }
        saveEvents()
        if e.hasAlarm { NotificationManager.shared.schedule(e, cat: category(for: e.categoryId)) }
    }
    func updateEvent(_ e: CalendarEvent) {
        guard let i = events.firstIndex(where: { $0.id == e.id }) else { return }
        guard events[i].sharePermission == .edit else { return }
        NotificationManager.shared.cancel(e.id)
        events[i] = e
        events.sort { $0.startDate < $1.startDate }
        saveEvents()
        if e.hasAlarm { NotificationManager.shared.schedule(e, cat: category(for: e.categoryId)) }
    }
    func deleteEvent(id: UUID) {
        if let e = events.first(where: { $0.id == id }), e.sharePermission == .view { return }
        NotificationManager.shared.cancel(id)
        events.removeAll { $0.id == id }
        saveEvents()
    }
    func events(for date: Date) -> [CalendarEvent] {
        visibleEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }
    }

    var visibleEvents: [CalendarEvent] {
        events.filter { canView(visibility: $0.visibility, ownerName: $0.ownerName, sharedWithNames: $0.sharedWithNames) }
    }

    func memberNames(for ids: [UUID]) -> [String] {
        ids.compactMap { id in
            members.first(where: { $0.id == id })?.name
        }
    }

    func conflictingEvents(for candidate: CalendarEvent, excluding eventId: UUID? = nil) -> [CalendarEvent] {
        guard !candidate.assignedMemberIds.isEmpty else { return [] }

        return visibleEvents.filter { existing in
            if existing.id == eventId { return false }
            let overlaps = candidate.startDate < existing.endDate && candidate.endDate > existing.startDate
            guard overlaps else { return false }
            return !Set(candidate.assignedMemberIds).intersection(existing.assignedMemberIds).isEmpty
        }
        .sorted { $0.startDate < $1.startDate }
    }

    @discardableResult
    func importSharedEnvelope(_ env: AuraShareEnvelope) -> Int {
        var imported = 0
        let fallbackCategory = categories.first?.id ?? EventCategory.defaults.first?.id
        for var e in env.events {
            guard let fallbackCategory else { continue }
            if category(for: e.categoryId) == nil {
                e.categoryId = fallbackCategory
            }
            e.sharedBy = env.senderName
            e.sharePermission = env.permission

            if let i = events.firstIndex(where: { $0.id == e.id }) {
                events[i] = e
            } else {
                events.append(e)
            }
            imported += 1
            recordSharedActivity(.init(
                timestamp: Date(),
                sender: env.senderName,
                eventTitle: e.title,
                action: .accepted,
                details: "Imported with \(env.permission.rawValue.lowercased()) access"
            ))
            NotificationManager.shared.cancel(e.id)
            if e.hasAlarm { NotificationManager.shared.schedule(e, cat: category(for: e.categoryId)) }
        }
        events.sort { $0.startDate < $1.startDate }
        saveEvents()
        return imported
    }

    func setSharePermission(id: UUID, permission: SharePermission) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        events[i].sharePermission = permission
        recordSharedActivity(.init(
            timestamp: Date(),
            sender: events[i].sharedBy ?? "Unknown",
            eventTitle: events[i].title,
            action: .permissionChanged,
            details: "Set to \(permission.rawValue)"
        ))
        saveEvents()
    }

    func revokeSharedEvent(id: UUID) {
        let evt = events.first(where: { $0.id == id })
        events.removeAll { $0.id == id }
        NotificationManager.shared.cancel(id)
        if let e = evt {
            recordSharedActivity(.init(
                timestamp: Date(),
                sender: e.sharedBy ?? "Unknown",
                eventTitle: e.title,
                action: .revoked,
                details: "Removed from your agenda"
            ))
        }
        saveEvents()
    }

    func loadSharedActivity() {
        if let d = shared.data(forKey: aKey),
           let v = try? JSONDecoder().decode([SharedActivityEntry].self, from: d) {
            sharedActivity = v.sorted { $0.timestamp > $1.timestamp }
        }
    }

    func saveSharedActivity() {
        if let d = try? JSONEncoder().encode(sharedActivity) {
            shared.set(d, forKey: aKey)
        }
    }

    func recordSharedActivity(_ entry: SharedActivityEntry) {
        sharedActivity.insert(entry, at: 0)
        if sharedActivity.count > 300 { sharedActivity = Array(sharedActivity.prefix(300)) }
        saveSharedActivity()
    }

    // ── Family Members ─────────────────────────────────────
    func loadMembers() {
        if let d = shared.data(forKey: mKey),
           let v = try? JSONDecoder().decode([FamilyMember].self, from: d),
           !v.isEmpty {
            members = v
        } else {
            members = [
                .init(name: "Mama", colorHex: "FF6B9D", role: "Parent"),
                .init(name: "Papa", colorHex: "4A90D9", role: "Parent"),
                .init(name: "Children", colorHex: "22C55E", role: "Kids")
            ]
            saveMembers()
        }
    }

    func saveMembers() {
        if let d = try? JSONEncoder().encode(members) {
            shared.set(d, forKey: mKey)
        }
        if !applyingRemoteSnapshot { queueSyncPush() }
    }

    func addMember(_ m: FamilyMember) {
        members.append(m)
        if activeFamilyMemberId.isEmpty {
            activeFamilyMemberId = m.id.uuidString
        }
        saveMembers()
    }

    func updateMember(_ member: FamilyMember) {
        guard let idx = members.firstIndex(where: { $0.id == member.id }) else { return }
        members[idx] = member
        saveMembers()
    }

    func setActiveMember(id: UUID?) {
        activeFamilyMemberId = id?.uuidString ?? ""
        objectWillChange.send()
    }

    func setMemberStepSharing(name: String, allows: Bool) {
        guard let idx = members.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        members[idx].allowsStepSharing = allows
        saveMembers()
    }

    func syncStepsForActiveMember() {
        guard var member = activeMember else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = await StepTrackingManager.shared.requestAuthorization()
            guard granted, let steps = await StepTrackingManager.shared.fetchTodaySteps() else {
                self.syncStatus = "Steps unavailable"
                return
            }
            member.allowsStepSharing = shareDailySteps
            self.updateMember(member)
            self.upsertDailySteps(steps)
            self.syncStatus = "Steps synced for \(member.name)"
        }
    }

    func setViewerName(_ name: String) {
        viewAsMemberName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        objectWillChange.send()
    }

    // ── Shared Family Lists ────────────────────────────────
    func loadFamilyLists() {
        if let d = shared.data(forKey: lKey),
           let v = try? JSONDecoder().decode([FamilyList].self, from: d) {
            familyLists = v.sorted { $0.createdAt > $1.createdAt }
        } else {
            familyLists = [
                .init(title: "Weekly Grocery", kind: .supermarket, createdAt: Date(), items: [])
            ]
            saveFamilyLists()
        }
    }

    func saveFamilyLists() {
        if let d = try? JSONEncoder().encode(familyLists) {
            shared.set(d, forKey: lKey)
        }
        if !applyingRemoteSnapshot { queueSyncPush() }
    }

    func addFamilyList(title: String, kind: FamilyListKind) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        familyLists.insert(.init(title: clean, kind: kind, createdAt: Date(), items: [], ownerName: activeProfileName, visibility: .family, sharedWithNames: []), at: 0)
        saveFamilyLists()
    }

    func addFamilyList(title: String, kind: FamilyListKind, visibility: VisibilityScope, sharedWithNames: [String]) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let allowed = sharedWithNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        familyLists.insert(
            .init(
                title: clean,
                kind: kind,
                createdAt: Date(),
                items: [],
                ownerName: activeProfileName,
                visibility: visibility,
                sharedWithNames: allowed
            ),
            at: 0
        )
        saveFamilyLists()
    }

    func deleteFamilyList(id: UUID) {
        familyLists.removeAll { $0.id == id }
        saveFamilyLists()
    }

    func addItem(to listId: UUID, item: FamilyListItem) {
        guard let i = familyLists.firstIndex(where: { $0.id == listId }) else { return }
        familyLists[i].items.append(item)
        saveFamilyLists()
    }

    func updateItem(listId: UUID, item: FamilyListItem) {
        guard let i = familyLists.firstIndex(where: { $0.id == listId }),
              let j = familyLists[i].items.firstIndex(where: { $0.id == item.id })
        else { return }
        familyLists[i].items[j] = item
        saveFamilyLists()
    }

    func toggleItem(listId: UUID, itemId: UUID) {
        guard let i = familyLists.firstIndex(where: { $0.id == listId }),
              let j = familyLists[i].items.firstIndex(where: { $0.id == itemId })
        else { return }
        familyLists[i].items[j].isDone.toggle()
        familyLists[i].items[j].completedByName = familyLists[i].items[j].isDone ? activeProfileName : nil
                familyLists[i].items[j].boughtAt = familyLists[i].items[j].isDone ? Date() : nil
        saveFamilyLists()
    }

    func deleteItem(listId: UUID, itemId: UUID) {
        guard let i = familyLists.firstIndex(where: { $0.id == listId }) else { return }
        familyLists[i].items.removeAll { $0.id == itemId }
        saveFamilyLists()
    }

    // ── Family Activities ──────────────────────────────────
    func loadFamilyActivities() {
        if let d = shared.data(forKey: fKey),
           let v = try? JSONDecoder().decode([FamilyActivity].self, from: d) {
            familyActivities = v.sorted { $0.date > $1.date }
        }
    }

    func saveFamilyActivities() {
        if let d = try? JSONEncoder().encode(familyActivities) {
            shared.set(d, forKey: fKey)
        }
        if !applyingRemoteSnapshot { queueSyncPush() }
    }

    func addActivity(_ a: FamilyActivity) {
        familyActivities.insert(a, at: 0)
        if familyActivities.count > 500 { familyActivities = Array(familyActivities.prefix(500)) }
        saveFamilyActivities()
    }

    func updateActivity(_ activity: FamilyActivity) {
        guard let idx = familyActivities.firstIndex(where: { $0.id == activity.id }) else { return }
        familyActivities[idx] = activity
        familyActivities.sort { $0.date > $1.date }
        saveFamilyActivities()
    }

    func deleteActivity(id: UUID) {
        familyActivities.removeAll { $0.id == id }
        saveFamilyActivities()
    }

    func canView(visibility: VisibilityScope, ownerName: String, sharedWithNames: [String]) -> Bool {
        switch visibility {
        case .family:
            return true
        case .personal:
            return ownerName.caseInsensitiveCompare(currentViewerName) == .orderedSame
        case .custom:
            if ownerName.caseInsensitiveCompare(currentViewerName) == .orderedSame { return true }
            return sharedWithNames.contains { $0.caseInsensitiveCompare(currentViewerName) == .orderedSame }
        }
    }

    var visibleFamilyLists: [FamilyList] {
        familyLists.filter { canView(visibility: $0.visibility, ownerName: $0.ownerName, sharedWithNames: $0.sharedWithNames) }
    }

    var visibleFamilyActivities: [FamilyActivity] {
        familyActivities.filter { canView(visibility: $0.visibility, ownerName: $0.ownerName, sharedWithNames: $0.sharedWithNames) }
    }

    func saveLiveActivitySession() {
        if let activeActivitySession,
           let data = try? JSONEncoder().encode(activeActivitySession) {
            shared.set(data, forKey: liveActivityKey)
        } else {
            shared.removeObject(forKey: liveActivityKey)
        }
    }

    func loadLiveActivitySession() {
        if let d = shared.data(forKey: liveActivityKey),
           let session = try? JSONDecoder().decode(LiveFamilyActivitySession.self, from: d) {
            activeActivitySession = session
        }
    }

    func startLiveActivity(kind: FamilyActivityKind, notes: String, participantIds: [UUID], visibility: VisibilityScope, sharedWithNames: [String]) {
        activeActivitySession = .init(
            kind: kind,
            startedAt: Date(),
            notes: notes,
            participantIds: participantIds,
            ownerName: activeProfileName,
            visibility: visibility,
            sharedWithNames: sharedWithNames
        )
        saveLiveActivitySession()
    }

    func stopLiveActivity(save: Bool) {
        guard let session = activeActivitySession else { return }
        if save {
            let duration = max(1, Int(Date().timeIntervalSince(session.startedAt) / 60))
            addActivity(.init(
                kind: session.kind,
                date: session.startedAt,
                durationMinutes: duration,
                notes: session.notes,
                participantIds: session.participantIds,
                ownerName: session.ownerName,
                visibility: session.visibility,
                sharedWithNames: session.sharedWithNames
            ))
        }
        activeActivitySession = nil
        saveLiveActivitySession()
    }

    func visibleSteps(for memberId: UUID) -> Int? {
        guard let member = members.first(where: { $0.id == memberId }), member.allowsStepSharing else { return nil }
        guard let snapshot = visibleFamilyStepSnapshots.first(where: {
            $0.ownerName.caseInsensitiveCompare(member.name) == .orderedSame && Calendar.current.isDateInToday($0.date)
        }) else { return nil }
        return snapshot.steps
    }

    func activityStepTotal(_ activity: FamilyActivity) -> Int {
        activity.participantIds.compactMap { visibleSteps(for: $0) }.reduce(0, +)
    }

    var visibleFamilyStepSnapshots: [FamilyStepSnapshot] {
        familyStepSnapshots.filter { canView(visibility: $0.visibility, ownerName: $0.ownerName, sharedWithNames: $0.sharedWithNames) }
    }

    func updateHouseholdCode(_ code: String) {
        householdCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if householdCode.isEmpty {
            syncStatus = "Sync disabled"
        } else {
            syncStatus = hasServerHousehold ? "Household code ready" : "Household linked"
            queueSyncPush()
        }
    }

    func updateBackendBaseURL(_ value: String) {
        backendBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if backendBaseURL.isEmpty && backendAuthToken.isEmpty {
            syncStatus = currentHouseholdCode.isEmpty ? "Sync disabled" : "Household linked"
        }
        objectWillChange.send()
    }

    func clearServerSession() {
        backendAuthToken = ""
        backendAccountEmail = ""
        backendHouseholdId = ""
        backendStoredHouseholdName = ""
        serverAccountEmail = ""
        serverHouseholdName = ""
        syncStatus = currentHouseholdCode.isEmpty ? "Sync disabled" : "Household linked"
        objectWillChange.send()
    }

    private func mapServerError(_ error: Error, fallbackStatus: String) -> Error {
        if let serverError = error as? AuraServerError {
            switch serverError {
            case .unauthorized:
                clearServerSession()
                syncStatus = "Session expired. Sign in again."
                return serverError
            case .networkUnavailable:
                syncStatus = "Network unavailable"
                return serverError
            default:
                syncStatus = fallbackStatus
                return serverError
            }
        }
        syncStatus = fallbackStatus
        return error
    }

    func registerServerAccount(email: String, password: String, displayName: String) async -> Result<Void, Error> {
        do {
            let response = try await AuraServerSyncEngine.shared.register(
                baseURL: currentBackendBaseURL,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            applyAuth(response)
            syncStatus = "Account created"
            await refreshServerContext()
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Account setup failed"))
        }
    }

    func loginServerAccount(email: String, password: String) async -> Result<Void, Error> {
        do {
            let response = try await AuraServerSyncEngine.shared.login(
                baseURL: currentBackendBaseURL,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            applyAuth(response)
            syncStatus = "Signed in"
            await refreshServerContext()
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Sign-in failed"))
        }
    }

    func refreshServerContext() async {
        guard hasServerSession else { return }
        do {
            let me = try await AuraServerSyncEngine.shared.me(baseURL: currentBackendBaseURL, token: backendAuthToken)
            backendAccountEmail = me.user.email
            serverAccountEmail = me.user.email
            profileDisplayName = me.user.displayName

            if me.membership != nil,
               let household = try? await AuraServerSyncEngine.shared.currentHousehold(baseURL: currentBackendBaseURL, token: backendAuthToken) {
                backendHouseholdId = household.household?.id ?? ""
                backendStoredHouseholdName = household.household?.name ?? ""
                serverHouseholdName = backendStoredHouseholdName
                if let code = household.household?.code {
                    householdCode = code
                }
            }
            syncStatus = hasServerHousehold ? "Server household connected" : "Signed in · household not linked"
        } catch {
            _ = mapServerError(error, fallbackStatus: "Server refresh failed")
        }
    }

    func createServerHousehold(name: String) async -> Result<String, Error> {
        guard hasServerSession else {
            return .failure(AuraServerError.requestFailed("Sign in before creating a household."))
        }
        do {
            let response = try await AuraServerSyncEngine.shared.createHousehold(
                baseURL: currentBackendBaseURL,
                token: backendAuthToken,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            backendHouseholdId = response.householdId
            householdCode = response.code
            backendStoredHouseholdName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            serverHouseholdName = backendStoredHouseholdName
            syncStatus = "Server household ready"
            await pushSnapshot()
            return .success(response.code)
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Create household failed"))
        }
    }

    func joinServerHousehold(code: String) async -> Result<Void, Error> {
        guard hasServerSession else {
            return .failure(AuraServerError.requestFailed("Sign in before joining a household."))
        }
        do {
            let response = try await AuraServerSyncEngine.shared.joinHousehold(
                baseURL: currentBackendBaseURL,
                token: backendAuthToken,
                code: code.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            backendHouseholdId = response.household.id
            backendStoredHouseholdName = response.household.name
            serverHouseholdName = response.household.name
            householdCode = response.household.code
            syncStatus = "Joined \(response.household.name)"
            await pullSnapshot()
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Join household failed"))
        }
    }

    func updateServerDisplayName(_ name: String) async -> Result<Void, Error> {
        guard hasServerSession else {
            return .failure(AuraServerError.requestFailed("Sign in before updating profile."))
        }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return .failure(AuraServerError.requestFailed("Display name cannot be empty."))
        }
        do {
            let response = try await AuraServerSyncEngine.shared.updateProfile(
                baseURL: currentBackendBaseURL,
                token: backendAuthToken,
                displayName: clean
            )
            profileDisplayName = response.user.displayName
            syncStatus = "Profile updated"
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Profile update failed"))
        }
    }

    func changeServerPassword(currentPassword: String, newPassword: String) async -> Result<Void, Error> {
        guard hasServerSession else {
            return .failure(AuraServerError.requestFailed("Sign in before changing password."))
        }
        guard newPassword.count >= 8 else {
            return .failure(AuraServerError.requestFailed("New password must be at least 8 characters."))
        }
        do {
            _ = try await AuraServerSyncEngine.shared.changePassword(
                baseURL: currentBackendBaseURL,
                token: backendAuthToken,
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            syncStatus = "Password changed"
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Password change failed"))
        }
    }

    private func applyAuth(_ response: AuraRemoteAuthResponse) {
        backendAuthToken = response.token
        backendAccountEmail = response.user.email
        serverAccountEmail = response.user.email
        profileDisplayName = response.user.displayName
        objectWillChange.send()
    }

    func queueSyncPush() {
        let canSync = hasServerHousehold || !currentHouseholdCode.isEmpty
        guard canSync else { return }
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await self?.pushSnapshot()
        }
    }

    func forceSyncNow() {
        let canSync = hasServerHousehold || !currentHouseholdCode.isEmpty
        guard canSync else { return }
        Task { [weak self] in
            await self?.pushSnapshot()
            await self?.pullSnapshot()
        }
    }

    private func startPeriodicPull() {
        periodicPullTask?.cancel()
        periodicPullTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let interval: UInt64 = self.hasServerHousehold ? 6_000_000_000 : 15_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                await self.pullSnapshot()
            }
        }
    }

    private func snapshotPayload() -> HouseholdSyncPayload {
        .init(
            updatedAt: Date(),
            updatedBy: activeProfileName,
            categories: categories,
            events: events,
            members: members,
            familyLists: familyLists,
            familyActivities: familyActivities
            ,stepSnapshots: familyStepSnapshots
        )
    }

    @MainActor
    private func pushSnapshot() async {
        do {
            if hasServerHousehold {
                _ = try await AuraServerSyncEngine.shared.uploadSnapshot(baseURL: currentBackendBaseURL, token: backendAuthToken, payload: snapshotPayload())
            } else {
                let code = currentHouseholdCode
                guard !code.isEmpty else { return }
                try await HouseholdSyncEngine.shared.upload(householdCode: code, payload: snapshotPayload())
            }
            householdLastSnapshot = Date().timeIntervalSince1970
            syncStatus = hasServerHousehold ? "Server synced just now" : "Synced just now"
        } catch {
            _ = mapServerError(error, fallbackStatus: hasServerHousehold ? "Server sync upload failed" : "Sync upload failed")
        }
    }

    @MainActor
    private func pullSnapshot() async {
        do {
            let incoming: HouseholdSyncPayload?
            if hasServerHousehold {
                incoming = try await AuraServerSyncEngine.shared.downloadSnapshot(baseURL: currentBackendBaseURL, token: backendAuthToken)
            } else {
                let code = currentHouseholdCode
                guard !code.isEmpty else { return }
                incoming = try await HouseholdSyncEngine.shared.download(householdCode: code)
            }
            guard let incoming else { return }
            guard incoming.updatedAt.timeIntervalSince1970 > householdLastSnapshot + 0.5 else { return }
            applyingRemoteSnapshot = true
            categories = incoming.categories
            events = incoming.events.sorted { $0.startDate < $1.startDate }
            members = incoming.members
            familyLists = incoming.familyLists.sorted { $0.createdAt > $1.createdAt }
            familyActivities = incoming.familyActivities.sorted { $0.date > $1.date }
            familyStepSnapshots = incoming.stepSnapshots.sorted { $0.updatedAt > $1.updatedAt }
            saveCats()
            saveEvents()
            saveMembers()
            saveFamilyLists()
            saveFamilyActivities()
            saveFamilyStepSnapshots()
            applyingRemoteSnapshot = false
            householdLastSnapshot = incoming.updatedAt.timeIntervalSince1970
            syncStatus = hasServerHousehold ? "Server updated from \(incoming.updatedBy)" : "Updated from \(incoming.updatedBy)"
        } catch {
            _ = mapServerError(error, fallbackStatus: hasServerHousehold ? "Server sync pull failed" : "Sync pull failed")
        }
    }

    func loadFamilyStepSnapshots() {
        if let d = shared.data(forKey: sKey),
           let v = try? JSONDecoder().decode([FamilyStepSnapshot].self, from: d) {
            familyStepSnapshots = v.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func saveFamilyStepSnapshots() {
        if let d = try? JSONEncoder().encode(familyStepSnapshots) {
            shared.set(d, forKey: sKey)
        }
        if !applyingRemoteSnapshot { queueSyncPush() }
    }

    func updateDailyStepSharing(enabled: Bool, visibility: VisibilityScope, sharedWithNames: [String]) {
        shareDailySteps = enabled
        dailyStepVisibilityRaw = visibility.rawValue
        dailyStepSharedWithNamesRaw = sharedWithNames.joined(separator: ",")
        setMemberStepSharing(name: activeProfileName, allows: enabled)
        refreshDailyStepsIfEnabled(force: true)
    }

    func refreshDailyStepsIfEnabled(force: Bool = false) {
        guard force || shareDailySteps else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = await StepTrackingManager.shared.requestAuthorization()
            guard granted, let steps = await StepTrackingManager.shared.fetchTodaySteps() else {
                self.syncStatus = "Steps unavailable"
                return
            }
            self.upsertDailySteps(steps)
        }
    }

    private func upsertDailySteps(_ steps: Int) {
        let today = Calendar.current.startOfDay(for: Date())
        let visibility = dailyStepVisibility
        let sharedNames = dailyStepSharedWithNames
        if let idx = familyStepSnapshots.firstIndex(where: {
            $0.ownerName.caseInsensitiveCompare(activeProfileName) == .orderedSame &&
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }) {
            familyStepSnapshots[idx].steps = steps
            familyStepSnapshots[idx].visibility = visibility
            familyStepSnapshots[idx].sharedWithNames = sharedNames
            familyStepSnapshots[idx].updatedAt = Date()
        } else {
            familyStepSnapshots.insert(
                .init(ownerName: activeProfileName, date: today, steps: steps, visibility: visibility, sharedWithNames: sharedNames, updatedAt: Date()),
                at: 0
            )
        }
        saveFamilyStepSnapshots()
    }
}

// MARK: - Notification Manager

class NotificationManager {
    static let shared = NotificationManager()

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func schedule(_ event: CalendarEvent, cat: EventCategory?) {
        let c = UNMutableNotificationContent()
        c.title = event.title
        c.body  = cat.map { $0.name } ?? "Event"
        if !event.location.isEmpty { c.subtitle = event.location }
        let appSound = event.soundOverride ?? cat?.sound ?? .systemDefault
        c.sound = appSound.unSound
        c.badge = 1

        let fire: Date
        if event.isAllDay {
            fire = Calendar.current.startOfDay(for: event.startDate)
        } else {
            fire = event.startDate.addingTimeInterval(-(Double(event.alarmMins) * 60))
        }
        guard fire > Date() else { return }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let req   = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: c,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        UNUserNotificationCenter.current().add(req)
    }

    func cancel(_ id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}

// MARK: - Root Content View

struct ContentView: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var shareManager: ShareManager
    @State private var tab = 0
    @State private var showCreate = false
    @State private var showImportResult = false
    @State private var importResultText = ""
    @State private var bannerPayload: InAppBannerPayload? = nil
    @State private var showQuickHomeActions = false
    @State private var showAddList = false
    @State private var showAddActivity = false
    @State private var showStartLiveActivity = false
    @State private var showQuickGrocery = false
    @State private var showAddMember = false
    @AppStorage("colorScheme") private var scheme = "system"
    @AppStorage("widgetThemeJSON") private var widgetThemeJSON = ""

    var preferredScheme: ColorScheme? {
        scheme == "light" ? .light : scheme == "dark" ? .dark : nil
    }
    var palette: AuraThemePalette { .from(themeJSON: widgetThemeJSON) }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                HomeView(showCreate: $showCreate)
                    .id("home-\(widgetThemeJSON)")
                    .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
                AgendaView(showCreate: $showCreate)
                    .id("agenda-\(widgetThemeJSON)")
                    .tabItem { Label("Agenda", systemImage: "list.bullet.rectangle") }.tag(1)
                CalendarView(showCreate: $showCreate)
                    .id("calendar-\(widgetThemeJSON)")
                    .tabItem { Label("Calendar", systemImage: "calendar") }.tag(2)
                ListsView()
                    .id("lists-\(widgetThemeJSON)")
                    .tabItem { Label("Lists", systemImage: "checklist") }.tag(3)
                SettingsView()
                    .id("settings-\(widgetThemeJSON)")
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(4)
            }
            .tint(palette.accentStart)

            VStack {
                if let b = bannerPayload {
                    AuraInAppBannerView(payload: b, palette: palette)
                        .padding(.top, 8)
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .animation(AuraMotion.banner, value: bannerPayload)

            // ── Floating Action Button ──────────────────────
            Button {
                AuraHaptics.tap(.medium)
                handlePrimaryAction()
            } label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [palette.accentStart, palette.accentEnd],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 60, height: 60)
                        .shadow(color: palette.accentStart.opacity(0.45), radius: 14, y: 5)
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .offset(y: -28)
            .scaleEffect(showCreate ? 0.96 : 1)
        }
        .preferredColorScheme(preferredScheme)
        .sheet(isPresented: $showCreate) {
            CreateEventView(isPresented: $showCreate).environmentObject(store)
        }
        .sheet(isPresented: $showAddList) {
            AddFamilyListView(isPresented: $showAddList).environmentObject(store)
        }
        .sheet(isPresented: $showAddActivity) {
            AddActivityView(isPresented: $showAddActivity).environmentObject(store)
        }
        .sheet(isPresented: $showStartLiveActivity) {
            StartLiveActivityView(isPresented: $showStartLiveActivity).environmentObject(store)
        }
        .sheet(isPresented: $showQuickGrocery) {
            QuickAddShoppingItemView(isPresented: $showQuickGrocery).environmentObject(store)
        }
        .sheet(isPresented: $showAddMember) {
            AddMemberView(isPresented: $showAddMember).environmentObject(store)
        }
        .confirmationDialog("Quick Actions", isPresented: $showQuickHomeActions, titleVisibility: .visible) {
            Button("Schedule Event") { showCreate = true }
            Button("Log Activity") { showAddActivity = true }
            Button("Start Live Activity") { showStartLiveActivity = true }
            Button("Add Grocery Item") { showQuickGrocery = true }
            Button("Create Shared List") { showAddList = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Shared Aura Data",
            isPresented: Binding(
                get: { shareManager.pendingImport != nil },
                set: { v in if !v { shareManager.pendingImport = nil } }
            ),
            presenting: shareManager.pendingImport
        ) { env in
            Button("Cancel", role: .cancel) { shareManager.pendingImport = nil }
            Button("Save") {
                let count = store.importSharedEnvelope(env)
                AuraHaptics.success()
                importResultText = "Imported \(count) event\(count == 1 ? "" : "s")."
                showImportResult = true
                shareManager.pendingImport = nil
            }
        } message: { env in
            Text("\(env.senderName) shared \(env.events.count) event\(env.events.count == 1 ? "" : "s") with \(env.permission.rawValue.lowercased()) access.")
        }
        .alert("Import Complete", isPresented: $showImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResultText)
        }
        .onAppear { styleTabBar() }
        .onChange(of: widgetThemeJSON) { _ in styleTabBar() }
        .onReceive(NotificationCenter.default.publisher(for: .auraInAppBanner)) { note in
            let title = (note.userInfo?["title"] as? String) ?? "Reminder"
            let msg = (note.userInfo?["message"] as? String) ?? ""
            bannerPayload = .init(title: title, message: msg)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                if bannerPayload?.title == title, bannerPayload?.message == msg {
                    bannerPayload = nil
                }
            }
        }
    }

    func styleTabBar() {
        let a = UITabBarAppearance()
        a.configureWithDefaultBackground()
        a.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        a.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.78)

        let item = UITabBarItemAppearance()
        item.normal.iconColor = .secondaryLabel
        item.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        item.selected.iconColor = UIColor(palette.accentStart)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(palette.accentStart)]
        a.stackedLayoutAppearance = item
        a.inlineLayoutAppearance = item
        a.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance   = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }

    func handlePrimaryAction() {
        switch tab {
        case 0:
            showQuickHomeActions = true
        case 1, 2:
            withAnimation(AuraMotion.spring) { showCreate = true }
        case 3:
            withAnimation(AuraMotion.spring) { showAddList = true }
        case 4:
            withAnimation(AuraMotion.spring) { showAddMember = true }
        default:
            withAnimation(AuraMotion.spring) { showCreate = true }
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var store: EventStore
    @Binding var showCreate: Bool
    @State private var showLogActivity = false
    @State private var showStartLiveActivity = false
    @State private var showQuickAddItem = false
    @State private var showOnlyShared = true
    @State private var editingActivity: FamilyActivity? = nil

    var todayEventsCount: Int {
        store.events(for: Date()).count
    }

    var pendingShoppingItems: Int {
        (showOnlyShared ? store.visibleFamilyLists : store.familyLists)
            .flatMap { $0.items }
            .filter { !$0.isDone }
            .count
    }

    var recentActivities: [FamilyActivity] {
        Array((showOnlyShared ? store.visibleFamilyActivities : store.familyActivities).prefix(3))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    HomeSectionCard(title: "Viewing As") {
                        Picker("Family Member", selection: Binding(
                            get: { store.activeMember?.id },
                            set: { store.setActiveMember(id: $0) }
                        )) {
                            ForEach(store.members) { member in
                                Text(member.name).tag(Optional(member.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Toggle("Show only what is visible to me", isOn: $showOnlyShared)
                        .font(.system(size: 13, weight: .semibold))

                    HomeHeroCard(
                        title: "Family Pulse",
                        subtitle: "\(todayEventsCount) events today · \(pendingShoppingItems) list items pending"
                    )

                    HStack(spacing: 10) {
                        HomeQuickActionButton(label: "Schedule Event", icon: "calendar.badge.plus") {
                            AuraHaptics.tap(.light)
                            showCreate = true
                        }
                        HomeQuickActionButton(label: "Log Activity", icon: "figure.walk") {
                            AuraHaptics.tap(.light)
                            showLogActivity = true
                        }
                    }

                    HStack(spacing: 10) {
                        HomeQuickActionButton(label: "Add Grocery", icon: "cart.badge.plus") {
                            AuraHaptics.tap(.light)
                            showQuickAddItem = true
                        }
                        HomeQuickActionButton(label: "Start Live", icon: "play.circle.fill") {
                            AuraHaptics.tap(.light)
                            showStartLiveActivity = true
                        }
                    }

                    if let session = store.activeActivitySession {
                        HomeSectionCard(title: "Live Activity") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("\(session.kind.rawValue) started \(session.startedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(session.notes.isEmpty ? "Live tracking in progress" : session.notes)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 10) {
                                    Button {
                                        AuraHaptics.success()
                                        store.stopLiveActivity(save: true)
                                    } label: {
                                        Label("Stop & Save", systemImage: "stop.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button(role: .destructive) {
                                        AuraHaptics.warning()
                                        store.stopLiveActivity(save: false)
                                    } label: {
                                        Label("Discard", systemImage: "xmark.circle")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }

                    HomeSectionCard(title: "Today") {
                        if store.events(for: Date()).isEmpty {
                            Text("No events today")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(store.events(for: Date()).prefix(4)) { e in
                                    HStack {
                                        Circle()
                                            .fill(store.category(for: e.categoryId)?.color ?? AuraThemePalette.current.accentStart)
                                            .frame(width: 8, height: 8)
                                        Text(e.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(timeLabel(e))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    HomeSectionCard(title: "Recent Family Activities") {
                        if recentActivities.isEmpty {
                            Text("No activities logged yet")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(recentActivities) { a in
                                    HStack(spacing: 10) {
                                        Image(systemName: a.kind.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                            .frame(width: 28, height: 28)
                                            .background(AuraThemePalette.current.accentStart.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(a.kind.rawValue)
                                                .font(.system(size: 14, weight: .semibold))
                                            Text(activitySubtitle(a))
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if store.activityStepTotal(a) > 0 {
                                            Text("\(store.activityStepTotal(a)) steps")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(AuraThemePalette.current.accentStart)
                                        }
                                        Menu {
                                            Button("Edit") {
                                                editingActivity = a
                                            }
                                            Button(role: .destructive) {
                                                store.deleteActivity(id: a.id)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            .navigationTitle("Home")
        }
        .sheet(isPresented: $showLogActivity) {
            AddActivityView(isPresented: $showLogActivity)
                .environmentObject(store)
        }
        .sheet(isPresented: $showStartLiveActivity) {
            StartLiveActivityView(isPresented: $showStartLiveActivity)
                .environmentObject(store)
        }
        .sheet(isPresented: $showQuickAddItem) {
            QuickAddShoppingItemView(isPresented: $showQuickAddItem)
                .environmentObject(store)
        }
        .sheet(item: $editingActivity) { activity in
            AddActivityView(isPresented: .constant(true), editingActivity: activity)
                .environmentObject(store)
        }
    }

    private func timeLabel(_ e: CalendarEvent) -> String {
        if e.isAllDay { return "All day" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: e.startDate)
    }

    private func activitySubtitle(_ a: FamilyActivity) -> String {
        let names = a.participantIds.compactMap { id in
            store.members.first(where: { $0.id == id })?.name
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        return "\(a.durationMinutes)m · \(names.joined(separator: ", ")) · \(f.string(from: a.date))"
    }
}

struct HomeHeroCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [AuraThemePalette.current.backgroundStart, AuraThemePalette.current.backgroundEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct HomeQuickActionButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(AuraThemePalette.current.accentStart)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(AuraThemePalette.current.accentStart.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct HomeSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Shared Lists Hub

struct ListsView: View {
    @EnvironmentObject var store: EventStore
    @State private var selectedKind: FamilyListKind? = nil
    @State private var selectedVisibility: VisibilityScope? = nil
    @State private var showAddList = false
    @State private var selectedList: FamilyList? = nil

    var filteredLists: [FamilyList] {
        let base = store.visibleFamilyLists
        let byKind = selectedKind == nil ? base : base.filter { $0.kind == selectedKind }
        return selectedVisibility == nil ? byKind : byKind.filter { $0.visibility == selectedVisibility }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "All", selected: selectedKind == nil) {
                                selectedKind = nil
                            }
                            ForEach(FamilyListKind.allCases, id: \.self) { kind in
                                FilterChip(title: kind.rawValue, selected: selectedKind == kind) {
                                    selectedKind = kind
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "Visible", selected: selectedVisibility == nil) {
                                selectedVisibility = nil
                            }
                            ForEach(VisibilityScope.allCases, id: \.self) { scope in
                                FilterChip(title: scope.rawValue, selected: selectedVisibility == scope) {
                                    selectedVisibility = scope
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }

                if filteredLists.isEmpty {
                    Section {
                        Text("No lists yet. Create your first shared family list.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Family Lists") {
                        ForEach(filteredLists) { list in
                            Button {
                                selectedList = list
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: list.kind.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AuraThemePalette.current.accentStart)
                                        .frame(width: 30, height: 30)
                                        .background(AuraThemePalette.current.accentStart.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(list.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text(summary(for: list))
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: list.visibility.icon)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteFamilyList(id: list.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddList = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddList) {
            AddFamilyListView(isPresented: $showAddList)
                .environmentObject(store)
        }
        .sheet(item: $selectedList) { list in
            FamilyListDetailView(listId: list.id)
                .environmentObject(store)
        }
    }

    private func summary(for list: FamilyList) -> String {
        let done = list.items.filter { $0.isDone }.count
        if list.kind == .supermarket {
            let stores = Set(list.items.compactMap { $0.preferredStore?.rawValue })
            return "\(list.items.count) items · \(done) done · \(stores.count) stores"
        }
        return "\(list.items.count) items · \(done) done"
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    selected
                        ? AnyShapeStyle(LinearGradient(colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

struct AddFamilyListView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var kind: FamilyListKind = .supermarket
    @State private var visibility: VisibilityScope = .family
    @State private var customNames: Set<String> = []

    var body: some View {
        NavigationView {
            Form {
                Section("List Name") {
                    TextField("e.g. Weekly Grocery", text: $title)
                }
                Section("List Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(FamilyListKind.allCases, id: \.self) { k in
                            Label(k.rawValue, systemImage: k.icon).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Visibility") {
                    Picker("Who can see this", selection: $visibility) {
                        ForEach(VisibilityScope.allCases, id: \.self) { s in
                            Label(s.rawValue, systemImage: s.icon).tag(s)
                        }
                    }
                    Text(visibility.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                if visibility == .custom {
                    Section("Share With") {
                        ForEach(store.members.map(\.name), id: \.self) { name in
                            Button {
                                if customNames.contains(name) {
                                    customNames.remove(name)
                                } else {
                                    customNames.insert(name)
                                }
                            } label: {
                                HStack {
                                    Text(name).foregroundColor(.primary)
                                    Spacer()
                                    if customNames.contains(name) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        AuraHaptics.success()
                        store.addFamilyList(
                            title: title,
                            kind: kind,
                            visibility: visibility,
                            sharedWithNames: Array(customNames)
                        )
                        isPresented = false
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct FamilyListDetailView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    let listId: UUID
    @State private var showAddItem = false
    @State private var editItem: FamilyListItem? = nil

    var list: FamilyList? {
        store.familyLists.first(where: { $0.id == listId })
    }

    var groupedItems: [(ShoppingStore, [FamilyListItem])] {
        guard let list, list.kind == .supermarket else { return [] }
        return ShoppingStore.allCases.compactMap { storeName in
            let items = list.items.filter { ($0.preferredStore ?? .others) == storeName }
            return items.isEmpty ? nil : (storeName, items)
        }
    }

    var body: some View {
        NavigationView {
            List {
                if let list {
                    if list.items.isEmpty {
                        Text("No items yet")
                            .foregroundColor(.secondary)
                    } else if list.kind == .supermarket {
                        ForEach(groupedItems, id: \.0) { storeGroup in
                            Section(storeGroup.0.rawValue) {
                                ForEach(storeGroup.1) { item in
                                    itemRow(item)
                                }
                            }
                        }
                    } else {
                        ForEach(list.items) { item in
                            itemRow(item)
                        }
                    }
                }
            }
            .navigationTitle(list?.title ?? "List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddFamilyListItemView(isPresented: $showAddItem, listId: listId)
                .environmentObject(store)
        }
        .sheet(item: $editItem) { item in
            AddFamilyListItemView(isPresented: .constant(true), listId: listId, editingItem: item)
                .environmentObject(store)
        }
    }

    private func itemSummary(_ item: FamilyListItem) -> String {
        var bits: [String] = []
        if !item.quantity.isEmpty { bits.append(item.quantity) }
        bits.append(item.preferredStore?.rawValue ?? "Store not set")
        if let dueDate = item.dueDate {
            let f = DateFormatter()
            f.dateStyle = .medium
            bits.append(f.string(from: dueDate))
        }
        if item.isDone, let completedBy = item.completedByName {
            bits.append("Bought by \(completedBy)")
        }
        return bits.joined(separator: " · ")
    }

    @ViewBuilder
    private func itemRow(_ item: FamilyListItem) -> some View {
        HStack(spacing: 10) {
            Button {
                AuraHaptics.tap(.light)
                withAnimation(AuraMotion.quick) {
                    store.toggleItem(listId: listId, itemId: item.id)
                }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(item.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .strikethrough(item.isDone)
                    .foregroundColor(item.isDone ? .secondary : .primary)
                Text(itemSummary(item))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let id = item.assignedMemberId,
               let m = store.members.first(where: { $0.id == id }) {
                Text(m.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(m.color)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editItem = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AuraThemePalette.current.accentStart)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteItem(listId: listId, itemId: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct AddFamilyListItemView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    @Binding var isPresented: Bool
    let listId: UUID
    var editingItem: FamilyListItem? = nil

    @State private var name = ""
    @State private var quantity = ""
    @State private var note = ""
    @State private var assignedMemberId: UUID? = nil
    @State private var preferredStore: ShoppingStore = .others
    @State private var dueDate = Date()
    @State private var hasDueDate = false

    private func closeView() {
        if editingItem == nil {
            isPresented = false
        } else {
            dismiss()
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Item") {
                    TextField("e.g. Milk", text: $name)
                    TextField("Quantity", text: $quantity)
                    Picker("Buy At", selection: $preferredStore) {
                        ForEach(ShoppingStore.allCases, id: \.self) { store in
                            Label(store.rawValue, systemImage: store.icon).tag(store)
                        }
                    }
                    Toggle("Set date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: [.date])
                    }
                }
                Section("Assignment") {
                    Picker("Assigned To", selection: $assignedMemberId) {
                        Text("Anyone").tag(UUID?.none)
                        ForEach(store.members) { m in
                            Text(m.name).tag(Optional(m.id))
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional note", text: $note)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { closeView() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editingItem == nil ? "Add" : "Save") {
                        AuraHaptics.success()
                        let item = FamilyListItem(
                            id: editingItem?.id ?? UUID(),
                            name: name,
                            quantity: quantity,
                            note: note,
                            isDone: editingItem?.isDone ?? false,
                            assignedMemberId: assignedMemberId,
                            preferredStore: preferredStore,
                            dueDate: hasDueDate ? dueDate : nil,
                            boughtAt: editingItem?.boughtAt
                        )
                        if editingItem == nil {
                            store.addItem(to: listId, item: item)
                        } else {
                            store.updateItem(listId: listId, item: item)
                        }
                        closeView()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let editingItem else { return }
                name = editingItem.name
                quantity = editingItem.quantity
                note = editingItem.note
                assignedMemberId = editingItem.assignedMemberId
                preferredStore = editingItem.preferredStore ?? .others
                if let due = editingItem.dueDate {
                    dueDate = due
                    hasDueDate = true
                }
            }
        }
    }
}

struct AddActivityView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    @Binding var isPresented: Bool
    var editingActivity: FamilyActivity? = nil
    @State private var kind: FamilyActivityKind = .walk
    @State private var date = Date()
    @State private var duration = 30
    @State private var notes = ""
    @State private var selectedMembers: Set<UUID> = []
    @State private var visibility: VisibilityScope = .family
    @State private var customNames: Set<String> = []

    private func closeView() {
        if editingActivity == nil {
            isPresented = false
        } else {
            dismiss()
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Activity") {
                    Picker("Type", selection: $kind) {
                        ForEach(FamilyActivityKind.allCases, id: \.self) { k in
                            Label(k.rawValue, systemImage: k.icon).tag(k)
                        }
                    }
                    DatePicker("Date", selection: $date)
                    Stepper(value: $duration, in: 5...300, step: 5) {
                        Text("Duration: \(duration) min")
                    }
                }
                Section("Participants") {
                    ForEach(store.members) { m in
                        Button {
                            if selectedMembers.contains(m.id) {
                                selectedMembers.remove(m.id)
                            } else {
                                selectedMembers.insert(m.id)
                            }
                        } label: {
                            HStack {
                                Circle().fill(m.color).frame(width: 10, height: 10)
                                Text(m.name).foregroundColor(.primary)
                                Spacer()
                                if selectedMembers.contains(m.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AuraThemePalette.current.accentStart)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Visibility") {
                    Picker("Who can see this", selection: $visibility) {
                        ForEach(VisibilityScope.allCases, id: \.self) { s in
                            Label(s.rawValue, systemImage: s.icon).tag(s)
                        }
                    }
                    Text(visibility.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                if visibility == .custom {
                    Section("Share With") {
                        ForEach(store.members.map(\.name), id: \.self) { name in
                            Button {
                                if customNames.contains(name) {
                                    customNames.remove(name)
                                } else {
                                    customNames.insert(name)
                                }
                            } label: {
                                HStack {
                                    Text(name).foregroundColor(.primary)
                                    Spacer()
                                    if customNames.contains(name) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Log Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { closeView() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editingActivity == nil ? "Save" : "Update") {
                        AuraHaptics.success()
                        let activity = FamilyActivity(
                            id: editingActivity?.id ?? UUID(),
                            kind: kind,
                            date: date,
                            durationMinutes: duration,
                            notes: notes,
                            participantIds: Array(selectedMembers),
                            ownerName: editingActivity?.ownerName ?? store.activeProfileName,
                            visibility: visibility,
                            sharedWithNames: Array(customNames)
                        )
                        if editingActivity == nil {
                            store.addActivity(activity)
                        } else {
                            store.updateActivity(activity)
                        }
                        closeView()
                    }
                }
            }
            .onAppear {
                guard let editingActivity else { return }
                kind = editingActivity.kind
                date = editingActivity.date
                duration = editingActivity.durationMinutes
                notes = editingActivity.notes
                selectedMembers = Set(editingActivity.participantIds)
                visibility = editingActivity.visibility
                customNames = Set(editingActivity.sharedWithNames)
            }
        }
    }
}

struct StartLiveActivityView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var kind: FamilyActivityKind = .walk
    @State private var notes = ""
    @State private var selectedMembers: Set<UUID> = []
    @State private var visibility: VisibilityScope = .family
    @State private var customNames: Set<String> = []

    var body: some View {
        NavigationView {
            Form {
                Section("Activity") {
                    Picker("Type", selection: $kind) {
                        ForEach(FamilyActivityKind.allCases, id: \.self) { kind in
                            Label(kind.rawValue, systemImage: kind.icon).tag(kind)
                        }
                    }
                }
                Section("Participants") {
                    ForEach(store.members) { member in
                        Button {
                            if selectedMembers.contains(member.id) {
                                selectedMembers.remove(member.id)
                            } else {
                                selectedMembers.insert(member.id)
                            }
                        } label: {
                            HStack {
                                Text(member.name).foregroundColor(.primary)
                                Spacer()
                                if selectedMembers.contains(member.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AuraThemePalette.current.accentStart)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Visibility") {
                    Picker("Who can see this", selection: $visibility) {
                        ForEach(VisibilityScope.allCases, id: \.self) { scope in
                            Label(scope.rawValue, systemImage: scope.icon).tag(scope)
                        }
                    }
                }
                if visibility == .custom {
                    Section("Share With") {
                        ForEach(store.members.map(\.name), id: \.self) { name in
                            Button {
                                if customNames.contains(name) { customNames.remove(name) } else { customNames.insert(name) }
                            } label: {
                                HStack {
                                    Text(name).foregroundColor(.primary)
                                    Spacer()
                                    if customNames.contains(name) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes)
                }
            }
            .navigationTitle("Start Live Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Start") {
                        store.startLiveActivity(kind: kind, notes: notes, participantIds: Array(selectedMembers), visibility: visibility, sharedWithNames: Array(customNames))
                        AuraHaptics.success()
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct QuickAddShoppingItemView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var quantity = ""
    @State private var preferredStore: ShoppingStore = .others
    @State private var assignedMemberId: UUID? = nil
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var firstSupermarketList: FamilyList? {
        store.visibleFamilyLists.first(where: { $0.kind == .supermarket }) ?? store.visibleFamilyLists.first
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Shopping Item") {
                    TextField("Item name", text: $name)
                    TextField("Quantity", text: $quantity)
                    Picker("Buy At", selection: $preferredStore) {
                        ForEach(ShoppingStore.allCases, id: \.self) { store in
                            Label(store.rawValue, systemImage: store.icon).tag(store)
                        }
                    }
                    Picker("Responsible", selection: $assignedMemberId) {
                        Text("Anyone").tag(UUID?.none)
                        ForEach(store.members) { member in
                            Text(member.name).tag(Optional(member.id))
                        }
                    }
                    Toggle("Set date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: [.date])
                    }
                }
                Section {
                    if let list = firstSupermarketList {
                        Text("Will be added to: \(list.title)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else {
                        Text("No list found. A Weekly Grocery list will be created automatically.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Quick Grocery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        AuraHaptics.success()
                        if firstSupermarketList == nil {
                            store.addFamilyList(title: "Weekly Grocery", kind: .supermarket, visibility: .family, sharedWithNames: [])
                        }
                        if let target = store.visibleFamilyLists.first(where: { $0.kind == .supermarket }) ?? store.visibleFamilyLists.first {
                            store.addItem(to: target.id, item: .init(name: name, quantity: quantity, note: "", isDone: false, assignedMemberId: assignedMemberId, preferredStore: preferredStore, dueDate: hasDueDate ? dueDate : nil, completedByName: nil, boughtAt: nil))
                        }
                        isPresented = false
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct AddMemberView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var role = "Parent"
    @State private var color = Color(hex: "6366F1")

    var body: some View {
        NavigationView {
            Form {
                Section("Member") {
                    TextField("Name", text: $name)
                    TextField("Role", text: $role)
                    ColorPicker("Color", selection: $color)
                }
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        AuraHaptics.success()
                        let member = FamilyMember(name: name, colorHex: color.toHex(), role: role, allowsStepSharing: false)
                        store.addMember(member)
                        store.setActiveMember(id: member.id)
                        isPresented = false
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct AuraInAppBannerView: View {
    let payload: InAppBannerPayload
    let palette: AuraThemePalette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(payload.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !payload.message.isEmpty {
                    Text(payload.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [palette.backgroundStart, palette.backgroundEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Agenda View

struct AgendaView: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var shareManager: ShareManager
    @Binding var showCreate: Bool
    @State private var q = ""
    @State private var selected: CalendarEvent?
    @State private var showShareAgenda = false
    @State private var scrollOffset: CGFloat = 0
    @Namespace private var eventHeroNamespace

    var todayEvents: [CalendarEvent] {
        store.events(for: Date()).sorted { $0.startDate < $1.startDate }
    }
    var nextTodayEvent: CalendarEvent? {
        todayEvents.first { $0.startDate >= Date() } ?? todayEvents.first
    }

    var filtered: [CalendarEvent] {
        q.isEmpty ? store.visibleEvents :
        store.visibleEvents.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.notes.localizedCaseInsensitiveContains(q) ||
            (store.category(for: $0.categoryId)?.name.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var grouped: [(Date, [CalendarEvent])] {
        let g = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.startDate) }
        return g.sorted { $0.key < $1.key }
    }

    var shareableAgendaEvents: [CalendarEvent] {
        Array(filtered.prefix(40))
    }

    var headerScale: CGFloat {
        let collapse = min(max(-scrollOffset / 180, 0), 1)
        return 1 - (collapse * 0.12)
    }

    var headerOpacity: CGFloat {
        let collapse = min(max(-scrollOffset / 220, 0), 1)
        return 1 - (collapse * 0.7)
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    GeometryReader { g in
                        Color.clear
                            .preference(key: AgendaScrollOffsetKey.self, value: g.frame(in: .named("agendaScroll")).minY)
                    }
                    .frame(height: 0)

                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if q.isEmpty {
                            TodayFocusCard(
                                totalToday: todayEvents.count,
                                nextEvent: nextTodayEvent,
                                showCreate: $showCreate
                            )
                            .scaleEffect(headerScale, anchor: .top)
                            .opacity(headerOpacity)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                            .animation(AuraMotion.smooth, value: headerScale)
                        }
                        if store.isBootstrapping {
                            AgendaSkeletonView()
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .transition(.opacity)
                        } else if filtered.isEmpty {
                            EmptyStateView()
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        } else {
                            ForEach(grouped, id: \.0) { date, evts in
                                Section {
                                    ForEach(evts) { e in
                                        EventRow(event: e, heroNamespace: eventHeroNamespace)
                                            .padding(.horizontal, 16).padding(.vertical, 4)
                                            .onTapGesture {
                                                AuraHaptics.tap(.light)
                                                withAnimation(AuraMotion.spring) { selected = e }
                                            }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    AuraHaptics.warning()
                                                    withAnimation(AuraMotion.smooth) { store.deleteEvent(id: e.id) }
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                            .swipeActions(edge: .leading) {
                                                Button {
                                                    AuraHaptics.tap(.light)
                                                    withAnimation(AuraMotion.spring) { selected = e }
                                                } label: {
                                                    Label("View", systemImage: "eye.fill")
                                                }
                                                .tint(AuraThemePalette.current.accentStart)
                                            }
                                    }
                                } header: {
                                    DateHeader(date: date)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 90)
                }

                if let e = selected {
                    EventDetailView(
                        event: e,
                        heroNamespace: eventHeroNamespace,
                        onClose: {
                            withAnimation(AuraMotion.spring) { selected = nil }
                        }
                    )
                    .environmentObject(store)
                    .environmentObject(shareManager)
                    .zIndex(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .coordinateSpace(name: "agendaScroll")
            .onPreferenceChange(AgendaScrollOffsetKey.self) { scrollOffset = $0 }
            .animation(AuraMotion.spring, value: selected?.id)
            .animation(AuraMotion.smooth, value: filtered.isEmpty)
            .searchable(text: $q, prompt: "Search events…")
            .navigationTitle("Aura")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showShareAgenda = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(shareableAgendaEvents.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showShareAgenda) {
            ShareAuraSheet(
                title: "Share Agenda",
                subtitle: "Share up to 40 events from your current agenda filter.",
                events: shareableAgendaEvents
            )
            .environmentObject(shareManager)
        }
    }
}

struct TodayFocusCard: View {
    let totalToday: Int
    let nextEvent: CalendarEvent?
    @Binding var showCreate: Bool

    var body: some View {
        let p = AuraThemePalette.current
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today Focus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(totalToday) event\(totalToday == 1 ? "" : "s") planned")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))
                }
                Spacer()
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
            }
            if let e = nextEvent {
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next: \(e.title)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(timeLabel(e))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    Spacer()
                }
                .padding(10)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [p.backgroundStart, p.backgroundEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .shadow(color: p.accentStart.opacity(0.22), radius: 14, y: 7)
    }

    private func timeLabel(_ e: CalendarEvent) -> String {
        if e.isAllDay { return "All day" }
        let f = DateFormatter()
        f.timeStyle = .short
        return "\(f.string(from: e.startDate)) - \(f.string(from: e.endDate))"
    }
}

struct ShareAuraSheet: View {
    @EnvironmentObject var shareManager: ShareManager
    @Environment(\.dismiss) var dismiss

    let title: String
    let subtitle: String
    let events: [CalendarEvent]

    @AppStorage("profileDisplayName") private var storedDisplayName = ""
    @State private var senderName = ""
    @State private var permission: SharePermission = .edit

    var shareURL: URL? {
        shareManager.makeShareURL(
            senderName: senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Aura User" : senderName.trimmingCharacters(in: .whitespacesAndNewlines),
            permission: permission,
            events: events
        )
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Sender") {
                    TextField("Your name", text: $senderName)
                }
                Section("Permission") {
                    Picker("Access", selection: $permission) {
                        ForEach(SharePermission.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(permission.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("What Will Be Shared") {
                    Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section {
                    if let u = shareURL {
                        ShareLink(item: u) {
                            Label("Share via AirDrop / Messages", systemImage: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    senderName = storedDisplayName.isEmpty ? "Aura User" : storedDisplayName
                }
            }
            .onChange(of: senderName) { v in
                storedDisplayName = v.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .onChange(of: permission) { p in
                if p == .edit {
                    AuraHaptics.success()
                } else {
                    AuraHaptics.tap(.light)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 60)
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [AuraThemePalette.current.accentStart.opacity(0.13), AuraThemePalette.current.accentEnd.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 140, height: 140)
                Circle()
                    .stroke(AuraThemePalette.current.accentStart.opacity(0.15), lineWidth: 1)
                    .frame(width: 140, height: 140)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(LinearGradient(
                        colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            VStack(spacing: 10) {
                Text("No Events Yet")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Tap + to schedule your first event")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Date Header

struct DateHeader: View {
    let date: Date
    var cal: Calendar { .current }

    var dayNum: String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }
    var weekday: String {
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInTomorrow(date)  { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: date)
    }
    var monthYear: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: date)
    }
    var isToday: Bool { cal.isDateInToday(date) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isToday
                          ? AnyShapeStyle(LinearGradient(colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color(.tertiarySystemBackground)))
                    .frame(width: 42, height: 42)
                Text(dayNum)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(isToday ? .white : .primary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(weekday)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isToday ? AuraThemePalette.current.accentStart : .primary)
                Text(monthYear)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct AgendaScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AgendaSkeletonView: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 74)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .redacted(reason: .placeholder)
            }
        }
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: CalendarEvent
    var heroNamespace: Namespace.ID? = nil
    @EnvironmentObject var store: EventStore

    var cat: EventCategory? { store.category(for: event.categoryId) }
    var catColor: Color { cat?.color ?? AuraThemePalette.current.accentStart }

    var startStr: String {
        guard !event.isAllDay else { return "All Day" }
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: event.startDate)
    }
    var endStr: String {
        guard !event.isAllDay else { return "" }
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: event.endDate)
    }

    var body: some View {
        HStack(spacing: 10) {
            // ── Time column ───────────────────────────────
            VStack(alignment: .trailing, spacing: 2) {
                Text(startStr)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(catColor)
                if !event.isAllDay {
                    Text(endStr)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 54, alignment: .trailing)

            // ── Card ─────────────────────────────────────
            Group {
                if let heroNamespace {
                    cardBody
                        .matchedGeometryEffect(id: "event-card-\(event.id.uuidString)", in: heroNamespace)
                } else {
                    cardBody
                }
            }
        }
    }

    var cardBody: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(catColor)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let c = cat {
                        HStack(spacing: 4) {
                            Image(systemName: c.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(c.name)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(catColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(catColor.opacity(0.18), in: Capsule())
                    }
                    if event.hasAlarm {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    if event.recurrence != .none {
                        Image(systemName: "repeat")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            Spacer()
        }
        .background(catColor.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(catColor.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: catColor.opacity(0.15), radius: 9, y: 4)
    }
}

// MARK: - Calendar View

enum CalendarScope: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
}

struct CalendarView: View {
    @EnvironmentObject var store: EventStore
    @Binding var showCreate: Bool
    @State private var selectedDate = Date()
    @State private var month = Date()
    @State private var selected: CalendarEvent?
    @State private var scope: CalendarScope = .month

    var cal: Calendar { .current }
    var weekStart: Date {
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        return cal.date(from: comps) ?? selectedDate
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Scope", selection: $scope) {
                    ForEach(CalendarScope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                Group {
                    switch scope {
                    case .day:
                        dayScope
                    case .week:
                        weekScope
                    case .month:
                        monthScope
                    case .year:
                        yearScope
                    }
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selected) { e in
            EventDetailView(event: e).environmentObject(store)
        }
    }

    var dayLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Today" }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: selectedDate)
    }

    @ViewBuilder
    var dayScope: some View {
        DateShiftHeader(
            title: dayLabel(for: selectedDate),
            onPrev: {
                selectedDate = cal.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                month = selectedDate
            },
            onNext: {
                selectedDate = cal.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                month = selectedDate
            }
        )
        dayPanel(for: selectedDate)
    }

    @ViewBuilder
    var weekScope: some View {
        DateShiftHeader(
            title: weekRangeLabel,
            onPrev: {
                selectedDate = cal.date(byAdding: .day, value: -7, to: selectedDate) ?? selectedDate
                month = selectedDate
            },
            onNext: {
                selectedDate = cal.date(byAdding: .day, value: 7, to: selectedDate) ?? selectedDate
                month = selectedDate
            }
        )
        WeekStrip(selectedDate: $selectedDate, weekStart: weekStart)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        dayPanel(for: selectedDate)
    }

    @ViewBuilder
    var monthScope: some View {
        MonthNav(month: $month)
        WeekdayRow()
        MonthGrid(month: month, selected: $selectedDate)
            .padding(.horizontal, 8)
        Divider().padding(.top, 6)
        dayPanel(for: selectedDate)
    }

    @ViewBuilder
    var yearScope: some View {
        DateShiftHeader(
            title: yearTitle,
            onPrev: { month = cal.date(byAdding: .year, value: -1, to: month) ?? month },
            onNext: { month = cal.date(byAdding: .year, value: 1, to: month) ?? month }
        )
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(1...12, id: \.self) { m in
                    YearMonthCard(
                        monthIndex: m,
                        yearDate: month,
                        eventCount: eventsCountForMonth(monthIndex: m, yearDate: month),
                        isCurrentMonth: isCurrentMonth(monthIndex: m, yearDate: month)
                    ) {
                        let y = cal.component(.year, from: month)
                        if let d = cal.date(from: DateComponents(year: y, month: m, day: 1)) {
                            month = d
                            selectedDate = d
                            scope = .month
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 90)
        }
    }

    @ViewBuilder
    func dayPanel(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(dayLabel(for: date))
                        .font(.system(size: 17, weight: .bold))
                    if cal.isDateInToday(date) {
                        Text("Today")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AuraThemePalette.current.accentStart)
                    }
                }
                Spacer()
                let count = store.events(for: date).count
                if count > 0 {
                    Text("\(count) event\(count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AuraThemePalette.current.accentStart)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(AuraThemePalette.current.accentStart.opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            if store.events(for: date).isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "moon.stars")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No events this day")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.events(for: date)) { e in
                            EventRow(event: e)
                                .padding(.horizontal, 16)
                                .onTapGesture { selected = e }
                        }
                    }
                    .padding(.bottom, 90)
                }
            }
        }
    }

    var weekRangeLabel: String {
        let end = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let yf = DateFormatter()
        yf.dateFormat = "yyyy"
        return "\(f.string(from: weekStart)) - \(f.string(from: end)), \(yf.string(from: weekStart))"
    }

    var yearTitle: String {
        let y = cal.component(.year, from: month)
        return "\(y)"
    }

    func dayLabel(for date: Date) -> String {
        if cal.isDateInToday(date) { return "Today" }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    func eventsCountForMonth(monthIndex: Int, yearDate: Date) -> Int {
        let y = cal.component(.year, from: yearDate)
        return store.visibleEvents.filter {
            let c = cal.dateComponents([.year, .month], from: $0.startDate)
            return c.year == y && c.month == monthIndex
        }.count
    }

    func isCurrentMonth(monthIndex: Int, yearDate: Date) -> Bool {
        let now = Date()
        return cal.component(.year, from: now) == cal.component(.year, from: yearDate)
            && cal.component(.month, from: now) == monthIndex
    }
}

struct DateShiftHeader: View {
    let title: String
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AuraThemePalette.current.accentStart)
                    .frame(width: 34, height: 34)
                    .background(AuraThemePalette.current.accentStart.opacity(0.12), in: Circle())
            }
            Spacer()
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Spacer()
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AuraThemePalette.current.accentStart)
                    .frame(width: 34, height: 34)
                    .background(AuraThemePalette.current.accentStart.opacity(0.12), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

struct WeekStrip: View {
    @Binding var selectedDate: Date
    let weekStart: Date

    var cal: Calendar { .current }

    var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { d in
                let selected = cal.isDate(d, inSameDayAs: selectedDate)
                Button {
                    selectedDate = d
                } label: {
                    VStack(spacing: 2) {
                        Text(weekdayShort(d))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(selected ? .white.opacity(0.9) : .secondary)
                        Text("\(cal.component(.day, from: d))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(selected ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        selected
                            ? AnyShapeStyle(LinearGradient(
                                colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            : AnyShapeStyle(Color(.tertiarySystemBackground))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "E"
        return f.string(from: d)
    }
}

struct YearMonthCard: View {
    let monthIndex: Int
    let yearDate: Date
    let eventCount: Int
    let isCurrentMonth: Bool
    let onTap: () -> Void

    var monthName: String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        let cal = Calendar.current
        let year = cal.component(.year, from: yearDate)
        let d = cal.date(from: DateComponents(year: year, month: monthIndex, day: 1)) ?? Date()
        return f.string(from: d)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(monthName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isCurrentMonth ? AuraThemePalette.current.accentStart : .primary)
                Text("\(eventCount)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(eventCount == 1 ? "event" : "events")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isCurrentMonth ? AuraThemePalette.current.accentStart.opacity(0.35) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Month Navigation

struct MonthNav: View {
    @Binding var month: Date
    var title: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: month)
    }
    var body: some View {
        HStack {
            NavBtn(dir: -1, month: $month)
            Spacer()
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .animation(.none, value: title)
            Spacer()
            NavBtn(dir: 1, month: $month)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct NavBtn: View {
    let dir: Int
    @Binding var month: Date
    var body: some View {
        Button {
            AuraHaptics.tap(.light)
            withAnimation(AuraMotion.smooth) {
                month = Calendar.current.date(byAdding: .month, value: dir, to: month)!
            }
        } label: {
            Image(systemName: dir < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AuraThemePalette.current.accentStart)
                .frame(width: 38, height: 38)
                .background(AuraThemePalette.current.accentStart.opacity(0.1), in: Circle())
        }
    }
}

// MARK: - Weekday Row

struct WeekdayRow: View {
    let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
    var body: some View {
        HStack {
            ForEach(days, id: \.self) { d in
                Text(d)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 2)
    }
}

// MARK: - Month Grid

struct MonthGrid: View {
    let month: Date
    @Binding var selected: Date
    @EnvironmentObject var store: EventStore

    var days: [Date?] {
        let cal   = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let range = cal.range(of: .day, in: .month, for: start)!
        let pad   = cal.component(.weekday, from: start) - 1
        var d: [Date?] = Array(repeating: nil, count: pad)
        for day in range {
            d.append(cal.date(byAdding: .day, value: day - 1, to: start))
        }
        while d.count % 7 != 0 { d.append(nil) }
        return d
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 2) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    DayCell(date: date, selected: $selected)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    @Binding var selected: Date
    @EnvironmentObject var store: EventStore

    var isSel:     Bool  { Calendar.current.isDate(date, inSameDayAs: selected) }
    var isToday:   Bool  { Calendar.current.isDateInToday(date) }
    var day:       Int   { Calendar.current.component(.day, from: date) }
    var evts:      [CalendarEvent] { store.events(for: date) }
    var hasEvents: Bool  { !evts.isEmpty }
    var dots:      [Color] {
        evts.prefix(3).compactMap { store.category(for: $0.categoryId)?.color }
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSel {
                    Circle()
                        .fill(LinearGradient(
                            colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                } else if isToday {
                    Circle()
                        .stroke(AuraThemePalette.current.accentStart, lineWidth: 2)
                        .frame(width: 34, height: 34)
                } else if hasEvents {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 34, height: 34)
                }
                Text("\(day)")
                    .font(.system(size: 14, weight: isSel || isToday ? .bold : hasEvents ? .semibold : .regular))
                    .foregroundColor(isSel ? .white : isToday ? AuraThemePalette.current.accentStart : .primary)
            }
            .frame(width: 36, height: 36)

            HStack(spacing: 2) {
                ForEach(Array(dots.enumerated()), id: \.offset) { _, c in
                    Circle().fill(c).frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .onTapGesture {
            AuraHaptics.tap(.light)
            withAnimation(AuraMotion.quick) { selected = date }
        }
    }
}

// MARK: - Event Detail View

struct EventDetailView: View {
    let event: CalendarEvent
    var heroNamespace: Namespace.ID? = nil
    var onClose: (() -> Void)? = nil
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var shareManager: ShareManager
    @Environment(\.dismiss) var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var showShare = false

    var cat: EventCategory? { store.category(for: event.categoryId) }
    var resolvedSound: AppSound { event.soundOverride ?? cat?.sound ?? .systemDefault }

    func closeDetail() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Banner ────────────────────────────────
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [
                                (cat?.color ?? Color(hex: "6366F1")).opacity(0.85),
                                cat?.color ?? Color(hex: "6366F1"),
                                (cat?.color ?? Color(hex: "6366F1")).opacity(0.6)
                            ],
                            startPoint: .topTrailing, endPoint: .bottomLeading)
                        .frame(height: 200)

                        // Large translucent icon in background
                        if let c = cat {
                            Image(systemName: c.icon)
                                .font(.system(size: 90, weight: .ultraLight))
                                .foregroundColor(.white.opacity(0.12))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 24)
                                .padding(.bottom, 16)
                        }

                        Group {
                            if let heroNamespace {
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(cat?.color ?? AuraThemePalette.current.accentStart)
                                        .frame(width: 5)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(event.title)
                                            .font(.system(size: 22, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        if let c = cat {
                                            HStack(spacing: 4) {
                                                Image(systemName: c.icon)
                                                    .font(.system(size: 10, weight: .semibold))
                                                Text(c.name)
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                            .foregroundColor(.white.opacity(0.95))
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(.white.opacity(0.22), in: Capsule())
                                        }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 11)
                                    Spacer()
                                }
                                .background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(.white.opacity(0.14), lineWidth: 1)
                                )
                                .matchedGeometryEffect(id: "event-card-\(event.id.uuidString)", in: heroNamespace)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let c = cat {
                                        HStack(spacing: 6) {
                                            Image(systemName: c.icon).font(.system(size: 12, weight: .semibold))
                                            Text(c.name).font(.system(size: 12, weight: .bold))
                                        }
                                        .foregroundColor(.white.opacity(0.95))
                                        .padding(.horizontal, 12).padding(.vertical, 5)
                                        .background(.white.opacity(0.22), in: Capsule())
                                    }
                                    Text(event.title)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                                }
                            }
                        }
                        .padding(22)
                    }

                    // ── Info Cards ────────────────────────────
                    VStack(spacing: 12) {
                        InfoCard(icon: "calendar", label: "Date",  value: fullDate)
                        if !event.isAllDay {
                            InfoCard(icon: "clock",   label: "Time",  value: fullTime)
                        }
                        if !event.location.isEmpty {
                            InfoCard(icon: "location.fill", label: "Location", value: event.location)
                        }
                        if event.hasAlarm {
                            InfoCard(icon: "bell.fill", label: "Reminder",
                                     value: "\(event.alarmMins) min before")
                            InfoCard(icon: resolvedSound.icon, label: "Alert Sound",
                                     value: resolvedSound.rawValue)
                        }
                        if event.recurrence != .none {
                            InfoCard(icon: "repeat", label: "Repeats", value: event.recurrence.rawValue)
                        }
                        if !event.notes.isEmpty {
                            InfoCard(icon: "note.text", label: "Notes", value: event.notes)
                        }
                        if !event.url.isEmpty {
                            InfoCard(icon: "link", label: "URL", value: event.url,
                                     tint: AuraThemePalette.current.accentStart)
                        }
                        if !event.assignedMemberIds.isEmpty {
                            InfoCard(icon: "person.2.fill", label: "Assigned To", value: assignedLabel)
                        }
                        InfoCard(icon: event.visibility.icon, label: "Visibility", value: visibilityLabel)
                        if !event.attachments.isEmpty {
                            AttachmentsCard(attachments: event.attachments)
                        }
                    }
                    .padding(16)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { closeDetail() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showShare = true } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        if event.sharePermission == .edit {
                            Button { showEdit = true } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Delete Event", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    AuraHaptics.warning()
                    store.deleteEvent(id: event.id)
                    closeDetail()
                }
            } message: {
                Text("Delete \"\(event.title)\"? This cannot be undone.")
            }
            .sheet(isPresented: $showEdit) {
                CreateEventView(isPresented: $showEdit, editing: event).environmentObject(store)
            }
            .sheet(isPresented: $showShare) {
                ShareAuraSheet(
                    title: "Share Event",
                    subtitle: "Send this event to another Aura user.",
                    events: [event]
                )
                .environmentObject(shareManager)
            }
        }
    }

    var fullDate: String {
        let f = DateFormatter(); f.dateStyle = .full; return f.string(from: event.startDate)
    }
    var fullTime: String {
        let f = DateFormatter(); f.timeStyle = .short
        return "\(f.string(from: event.startDate)) – \(f.string(from: event.endDate))"
    }
    var assignedLabel: String {
        event.assignedMemberIds.compactMap { id in
            store.members.first(where: { $0.id == id })?.name
        }.joined(separator: ", ")
    }
    var visibilityLabel: String {
        switch event.visibility {
        case .personal:
            return "Personal"
        case .family:
            return "Whole family"
        case .custom:
            let custom = event.sharedWithNames.joined(separator: ", ")
            return custom.isEmpty ? "Custom" : "Shared with \(custom)"
        }
    }
}

// MARK: - Info Card

struct InfoCard: View {
    let icon, label, value: String
    var tint: Color = AuraThemePalette.current.accentStart

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 15))
                .foregroundColor(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                Text(value).font(.system(size: 15))
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

// MARK: - Attachments Card

struct AttachmentsCard: View {
    let attachments: [Attachment]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Attachments", systemImage: "paperclip")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
            ForEach(attachments) { a in AttRow(a: a) }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct AttRow: View {
    let a: Attachment

    var icon: String {
        switch a.kind {
        case .image:    return "photo"
        case .pdf:      return "doc.richtext"
        case .document: return "doc.text"
        case .other:    return "paperclip"
        }
    }

    var size: String {
        let kb = Double(a.data.count) / 1024
        return kb < 1024
            ? String(format: "%.1f KB", kb)
            : String(format: "%.1f MB", kb / 1024)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 18))
                .foregroundColor(AuraThemePalette.current.accentStart)
                .frame(width: 34, height: 34)
                .background(AuraThemePalette.current.accentStart.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(a.filename)
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(size).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Create / Edit Event

struct CreateEventView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    var editing: CalendarEvent? = nil

    @State private var title      = ""
    @State private var notes      = ""
    @State private var start      = Date()
    @State private var end        = Date().addingTimeInterval(3600)
    @State private var allDay     = false
    @State private var catId: UUID = EventCategory.defaults.first!.id
    @State private var location   = ""
    @State private var hasAlarm   = true
    @State private var alarmMins  = 15
    @State private var recurrence: Recurrence = .none
    @State private var url        = ""
    @State private var attachments: [Attachment] = []
    @State private var photos:    [PhotosPickerItem] = []
    @State private var showFiles  = false
    @State private var showRepeatPicker = false
    @State private var soundOverride: AppSound?  = nil
    @State private var showSoundPicker           = false
    @State private var visibility: VisibilityScope = .family
    @State private var sharedWithNames: Set<String> = []
    @State private var assignedMemberIds: Set<UUID> = []

    let alarmOpts = [0, 5, 10, 15, 30, 60, 120, 1440]

    var draftEvent: CalendarEvent {
        CalendarEvent(
            id: editing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            notes: notes,
            startDate: start,
            endDate: end,
            isAllDay: allDay,
            categoryId: catId,
            location: location,
            alarmMins: alarmMins,
            hasAlarm: hasAlarm,
            url: url,
            attachments: attachments,
            recurrence: recurrence,
            soundOverride: soundOverride,
            sharedBy: editing?.sharedBy,
            sharePermission: editing?.sharePermission ?? .edit,
            ownerName: editing?.ownerName.isEmpty == false ? editing!.ownerName : store.activeProfileName,
            visibility: visibility,
            sharedWithNames: Array(sharedWithNames),
            assignedMemberIds: Array(assignedMemberIds)
        )
    }

    var conflicts: [CalendarEvent] {
        store.conflictingEvents(for: draftEvent, excluding: editing?.id)
    }

    var body: some View {
        NavigationView {
            Form {
                formTopSections
                formBottomSections
            }
            .navigationTitle(editing == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRepeatPicker) {
                RecurrencePickerSheet(selected: $recurrence, isPresented: $showRepeatPicker)
            }
            .sheet(isPresented: $showSoundPicker) {
                SoundPickerSheet(
                    isPresented: $showSoundPicker,
                    currentSound: soundOverride ?? .systemDefault,
                    showClearOption: true,
                    onSelect: { soundOverride = $0 },
                    onClear: { soundOverride = nil }
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editing == nil ? "Add" : "Update") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.bold)
                }
            }
            .onChange(of: photos) { items in
                Task {
                    for item in items {
                        if let d = try? await item.loadTransferable(type: Data.self) {
                            attachments.append(.init(
                                filename: "Photo_\(UUID().uuidString.prefix(6)).jpg",
                                data: d, kind: .image))
                        }
                    }
                    photos = []
                }
            }
            .fileImporter(
                isPresented: $showFiles,
                allowedContentTypes: [.pdf, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result,
                   let u = urls.first,
                   u.startAccessingSecurityScopedResource() {
                    defer { u.stopAccessingSecurityScopedResource() }
                    if let d = try? Data(contentsOf: u) {
                        let k: Attachment.AttKind =
                            u.pathExtension.lowercased() == "pdf" ? .pdf : .document
                        attachments.append(.init(filename: u.lastPathComponent, data: d, kind: k))
                    }
                }
            }
        }
        .onAppear { preload() }
    }

    @ViewBuilder
    private var formTopSections: some View {
        Section("Title") {
            TextField("Event title…", text: $title)
                .font(.system(size: 17, weight: .semibold))
        }
        Section("Category") {
            Picker("Category", selection: $catId) {
                ForEach(store.categories) { c in
                    CategoryPickerRow(category: c).tag(c.id)
                }
            }
            .pickerStyle(.menu)
        }
        Section("Who Is This For?") {
            ForEach(store.members) { member in
                Button {
                    if assignedMemberIds.contains(member.id) {
                        assignedMemberIds.remove(member.id)
                    } else {
                        assignedMemberIds.insert(member.id)
                    }
                } label: {
                    HStack {
                        Circle().fill(member.color).frame(width: 10, height: 10)
                        Text(member.name).foregroundColor(.primary)
                        Spacer()
                        if assignedMemberIds.contains(member.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AuraThemePalette.current.accentStart)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        Section("Visibility") {
            Picker("Who can see this", selection: $visibility) {
                ForEach(VisibilityScope.allCases, id: \.self) { scope in
                    Label(scope.rawValue, systemImage: scope.icon).tag(scope)
                }
            }
            Text(visibility.subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        if visibility == .custom {
            Section("Share With") {
                ForEach(store.members.map(\.name), id: \.self) { name in
                    Button {
                        if sharedWithNames.contains(name) {
                            sharedWithNames.remove(name)
                        } else {
                            sharedWithNames.insert(name)
                        }
                    } label: {
                        HStack {
                            Text(name).foregroundColor(.primary)
                            Spacer()
                            if sharedWithNames.contains(name) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AuraThemePalette.current.accentStart)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Section("When") {
            Toggle("All Day", isOn: $allDay)
            DatePicker("Start", selection: $start,
                       displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            DatePicker("End", selection: $end, in: start...,
                       displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
            Button { showRepeatPicker = true } label: {
                HStack {
                    Label("Repeats", systemImage: recurrence.icon)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(recurrence.rawValue)
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
        }
        Section("Reminder") {
            Toggle("Enable Alarm", isOn: $hasAlarm)
            if hasAlarm {
                Picker("Remind me", selection: $alarmMins) {
                    ForEach(alarmOpts, id: \.self) { Text(alarmLabel($0)).tag($0) }
                }
                Button { showSoundPicker = true } label: {
                    HStack {
                        Label("Sound", systemImage: (soundOverride ?? .systemDefault).icon)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(soundOverride?.rawValue ?? "Category Default")
                            .foregroundColor(.secondary)
                            .font(.system(size: 15))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var formBottomSections: some View {
        if !conflicts.isEmpty {
            Section("Potential Conflicts") {
                ForEach(conflicts) { conflict in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(conflict.title)
                            .font(.system(size: 14, weight: .semibold))
                        Text(conflictTimeLabel(conflict))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(store.memberNames(for: conflict.assignedMemberIds).joined(separator: ", "))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AuraThemePalette.current.accentStart)
                    }
                }
                Text("These family members are already booked during this time. You can still save if this overlap is intentional.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        Section("Details") {
            TextField("Location", text: $location)
            TextField("URL / Meeting link", text: $url)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        Section("Notes") {
            TextEditor(text: $notes).frame(minHeight: 80)
        }
        Section("Attachments") {
            PhotosPicker(selection: $photos, matching: .images, photoLibrary: .shared()) {
                Label("Add Photo", systemImage: "photo.on.rectangle.angled")
            }
            Button { showFiles = true } label: {
                Label("Add File", systemImage: "doc.badge.plus")
            }
            ForEach(attachments) { a in AttRow(a: a) }
                .onDelete { attachments.remove(atOffsets: $0) }
        }
    }

    func preload() {
        catId = store.categories.first?.id ?? catId
        if editing == nil, let activeMember = store.activeMember {
            assignedMemberIds = [activeMember.id]
        }
        guard let e = editing else { return }
        title       = e.title
        notes       = e.notes
        start       = e.startDate
        end         = e.endDate
        allDay      = e.isAllDay
        catId       = e.categoryId
        location    = e.location
        hasAlarm    = e.hasAlarm
        alarmMins     = e.alarmMins
        recurrence    = e.recurrence
        soundOverride = e.soundOverride
        url           = e.url
        attachments = e.attachments
        visibility = e.visibility
        sharedWithNames = Set(e.sharedWithNames)
        assignedMemberIds = Set(e.assignedMemberIds)
    }

    func save() {
        AuraHaptics.success()
        editing == nil ? store.addEvent(draftEvent) : store.updateEvent(draftEvent)
        isPresented = false
    }

    func conflictTimeLabel(_ event: CalendarEvent) -> String {
        if event.isAllDay { return "All day" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "\(f.string(from: event.startDate)) - \(DateFormatter.localizedString(from: event.endDate, dateStyle: .none, timeStyle: .short))"
    }

    func alarmLabel(_ m: Int) -> String {
        switch m {
        case 0:    return "At event time"
        case 60:   return "1 hour before"
        case 120:  return "2 hours before"
        case 1440: return "1 day before"
        default:   return "\(m) minutes before"
        }
    }
}

// MARK: - Category Picker Row (extracted to help type-checker)

private struct CategoryPickerRow: View {
    let category: EventCategory
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(category.color).frame(width: 10, height: 10)
            Image(systemName: category.icon)
            Text(category.name)
        }
    }
}

// MARK: - Recurrence Picker Sheet

struct RecurrencePickerSheet: View {
    @Binding var selected: Recurrence
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List {
                ForEach(Recurrence.allCases, id: \.self) { r in
                    Button {
                        AuraHaptics.tap(.medium)
                        selected = r
                        isPresented = false
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selected == r
                                          ? LinearGradient(colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                          : LinearGradient(colors: [Color(.tertiarySystemBackground), Color(.tertiarySystemBackground)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 40, height: 40)
                                Image(systemName: r.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(selected == r ? .white : Color(hex: "6366F1"))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.rawValue)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(r.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selected == r {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(LinearGradient(
                                        colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .font(.system(size: 20))
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Sound Picker Sheet

struct SoundPickerSheet: View {
    @Binding var isPresented: Bool
    var currentSound:    AppSound
    var showClearOption: Bool         = false
    var onSelect:        (AppSound) -> Void
    var onClear:         (() -> Void)? = nil

    var body: some View {
        NavigationView {
            List {
                if showClearOption {
                    Button {
                        AuraHaptics.tap(.medium)
                        onClear?()
                        isPresented = false
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.tertiarySystemBackground))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(hex: "6366F1"))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Same as Category")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("Uses the sound set for this event's category")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(AppSound.allCases, id: \.self) { s in
                    Button {
                        AuraHaptics.tap(.medium)
                        onSelect(s)
                        isPresented = false
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(currentSound == s
                                          ? LinearGradient(colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                          : LinearGradient(colors: [Color(.tertiarySystemBackground), Color(.tertiarySystemBackground)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 40, height: 40)
                                Image(systemName: s.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(currentSound == s ? .white : Color(hex: "6366F1"))
                            }
                            Text(s.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                            if currentSound == s {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(LinearGradient(
                                        colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .font(.system(size: 20))
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Alert Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Widget Gradient Theme

struct WidgetGradientTheme: Codable, Identifiable, Equatable {
    var id        = UUID()
    var name:     String
    var c1, c2:   String   // background start/end hex
    var n1, n2:   String   // number gradient start/end hex
    var isPreset: Bool = false

    static let presets: [WidgetGradientTheme] = [
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!, name: "Indigo Night",  c1:"1E1B4B", c2:"4C1D95", n1:"6366F1", n2:"A78BFA", isPreset:true),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!, name: "Ocean Deep",    c1:"0F172A", c2:"1E3A5F", n1:"38BDF8", n2:"7DD3FC", isPreset:true),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!, name: "Rose Noir",     c1:"1A0A2E", c2:"6B1A3A", n1:"F472B6", n2:"FDA4AF", isPreset:true),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000004")!, name: "Forest Dusk",   c1:"022C22", c2:"064E3B", n1:"34D399", n2:"6EE7B7", isPreset:true),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000005")!, name: "Amber Ember",   c1:"1C0A00", c2:"78350F", n1:"FB923C", n2:"FCD34D", isPreset:true),
        .init(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000006")!, name: "Midnight Grey", c1:"0F0F0F", c2:"1A1A1A", n1:"E5E5E5", n2:"FFFFFF", isPreset:true),
    ]
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: EventStore
    @AppStorage("colorScheme") private var scheme = "system"
    @AppStorage("widgetThemeJSON") private var widgetThemeJSON = ""
    @AppStorage("profileDisplayName") private var profileDisplayName = ""
    @AppStorage("householdCode") private var householdCode = ""
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @AppStorage("backendAccountEmail") private var backendAccountEmail = ""
    @AppStorage("backendHouseholdName") private var backendStoredHouseholdName = ""
    @AppStorage("enableInAppBanner") private var enableInAppBanner = true
    @AppStorage("shareDailySteps") private var shareDailySteps = false
    @AppStorage("dailyStepVisibility") private var dailyStepVisibilityRaw = VisibilityScope.personal.rawValue
    @AppStorage("dailyStepSharedWithNames") private var dailyStepSharedWithNamesRaw = ""
    @State private var showAdd = false
    @State private var showGradientBuilder = false
    @State private var showCategoryManager = false
    @State private var showSharedManager = false
    @State private var showSharedActivityLog = false
    @State private var showAddMember = false
    @State private var stepCustomNames: Set<String> = []
    @State private var customThemes: [WidgetGradientTheme] = []
    @State private var selectedThemeId: UUID? = WidgetGradientTheme.presets.first?.id
    @State private var editSoundCatId:  UUID?     = nil
    @State private var catSoundVal:     AppSound   = .systemDefault
    @State private var showCatSound:    Bool       = false
    @State private var serverEmail = ""
    @State private var serverPassword = ""
    @State private var serverDisplayName = ""
    @State private var householdNameDraft = "My Family"
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var serverMessage = ""
    @State private var isServerWorking = false

    var allThemes: [WidgetGradientTheme] { WidgetGradientTheme.presets + customThemes }
    var selectedTheme: WidgetGradientTheme? { allThemes.first { $0.id == selectedThemeId } }
    var dailyStepVisibility: VisibilityScope { VisibilityScope(rawValue: dailyStepVisibilityRaw) ?? .personal }
    var dailyStepSharedWithNames: [String] {
        dailyStepSharedWithNamesRaw.split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
    }
    var sharedBySender: [(String, Int)] {
        let grouped = Dictionary(grouping: store.events.filter { $0.sharedBy != nil }) { $0.sharedBy ?? "Unknown" }
        return grouped
            .map { ($0.key, $0.value.count) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            List {
                // ── Appearance ────────────────────────────────
                Section("Appearance") {
                    Picker("Theme", selection: $scheme) {
                        Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                        Label("Light",  systemImage: "sun.max.fill").tag("light")
                        Label("Dark",   systemImage: "moon.fill").tag("dark")
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.icloud")
                            .foregroundColor(AuraThemePalette.current.accentStart)
                        Text("Account & Server controls are here.")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("Use this section for Railway URL, sign-in, and account management.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } header: {
                    Text("Account & Server (Railway Sync)")
                }

                Section("Family Member") {
                    Picker("Viewing as", selection: Binding(
                        get: { store.activeMember?.id },
                        set: { store.setActiveMember(id: $0) }
                    )) {
                        ForEach(store.members) { member in
                            Text(member.name).tag(Optional(member.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        showAddMember = true
                    } label: {
                        Label("Add Family Member", systemImage: "person.badge.plus")
                    }
                }

                Section {
                    Toggle("Share my daily steps", isOn: Binding(
                        get: { shareDailySteps },
                        set: { newValue in
                            shareDailySteps = newValue
                            store.updateDailyStepSharing(enabled: newValue, visibility: dailyStepVisibility, sharedWithNames: Array(stepCustomNames))
                        }
                    ))

                    Picker("Step Visibility", selection: Binding(
                        get: { dailyStepVisibility },
                        set: { newValue in
                            dailyStepVisibilityRaw = newValue.rawValue
                            store.updateDailyStepSharing(enabled: shareDailySteps, visibility: newValue, sharedWithNames: Array(stepCustomNames))
                        }
                    )) {
                        ForEach(VisibilityScope.allCases, id: \.self) { scope in
                            Label(scope.rawValue, systemImage: scope.icon).tag(scope)
                        }
                    }

                    if dailyStepVisibility == .custom {
                        ForEach(store.members.map(\.name), id: \.self) { name in
                            Button {
                                if stepCustomNames.contains(name) {
                                    stepCustomNames.remove(name)
                                } else {
                                    stepCustomNames.insert(name)
                                }
                                dailyStepSharedWithNamesRaw = Array(stepCustomNames).joined(separator: ",")
                                store.updateDailyStepSharing(enabled: shareDailySteps, visibility: dailyStepVisibility, sharedWithNames: Array(stepCustomNames))
                            } label: {
                                HStack {
                                    Text(name).foregroundColor(.primary)
                                    Spacer()
                                    if stepCustomNames.contains(name) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        store.syncStepsForActiveMember()
                    } label: {
                        Label("Sync My Steps Now", systemImage: "figure.walk.motion")
                    }

                    if let activeMember = store.activeMember {
                        LabeledContent("Today") {
                            Text(activeMember.allowsStepSharing ? "Shared" : "Private")
                        }
                    }
                } header: {
                    Text("Daily Steps")
                } footer: {
                    Text("The active family member can choose whether their steps are visible to others.")
                }

                Section {
                    TextField("Backend URL", text: Binding(
                        get: { backendBaseURL },
                        set: {
                            backendBaseURL = $0
                            store.updateBackendBaseURL($0)
                        }
                    ))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                    if store.hasServerSession {
                        LabeledContent("Signed in as", value: store.serverAccountEmail.isEmpty ? backendAccountEmail : store.serverAccountEmail)
                        LabeledContent("Sync backend", value: store.currentSyncBackendLabel)

                        TextField("Display name", text: $serverDisplayName)
                        Button {
                            isServerWorking = true
                            serverMessage = ""
                            Task {
                                let result = await store.updateServerDisplayName(serverDisplayName)
                                await MainActor.run {
                                    isServerWorking = false
                                    switch result {
                                    case .success:
                                        profileDisplayName = serverDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        serverMessage = "Profile updated."
                                    case .failure(let error):
                                        serverMessage = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Label("Save Profile", systemImage: "person.crop.circle.badge.checkmark")
                        }

                        SecureField("Current password", text: $currentPassword)
                        SecureField("New password (min 8)", text: $newPassword)
                        Button {
                            isServerWorking = true
                            serverMessage = ""
                            Task {
                                let result = await store.changeServerPassword(currentPassword: currentPassword, newPassword: newPassword)
                                await MainActor.run {
                                    isServerWorking = false
                                    switch result {
                                    case .success:
                                        currentPassword = ""
                                        newPassword = ""
                                        serverMessage = "Password updated."
                                    case .failure(let error):
                                        serverMessage = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Label("Change Password", systemImage: "key.fill")
                        }
                        .disabled(currentPassword.isEmpty || newPassword.count < 8)

                        Button {
                            isServerWorking = true
                            serverMessage = ""
                            Task {
                                await store.refreshServerContext()
                                await MainActor.run {
                                    isServerWorking = false
                                }
                            }
                        } label: {
                            Label("Refresh Server Account", systemImage: "arrow.clockwise.circle")
                        }

                        Button(role: .destructive) {
                            store.clearServerSession()
                            serverPassword = ""
                            serverMessage = "Signed out."
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        TextField("Email", text: $serverEmail)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.emailAddress)
                        SecureField("Password", text: $serverPassword)
                        TextField("Display name", text: $serverDisplayName)

                        Button {
                            isServerWorking = true
                            serverMessage = ""
                            Task {
                                let result = await store.registerServerAccount(email: serverEmail, password: serverPassword, displayName: serverDisplayName)
                                await MainActor.run {
                                    isServerWorking = false
                                    switch result {
                                    case .success:
                                        serverMessage = "Account created successfully."
                                        serverPassword = ""
                                    case .failure(let error):
                                        serverMessage = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Label("Create Account", systemImage: "person.badge.plus")
                        }
                        .disabled(backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || serverEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || serverPassword.count < 8 || serverDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            isServerWorking = true
                            serverMessage = ""
                            Task {
                                let result = await store.loginServerAccount(email: serverEmail, password: serverPassword)
                                await MainActor.run {
                                    isServerWorking = false
                                    switch result {
                                    case .success:
                                        serverMessage = "Signed in successfully."
                                        serverPassword = ""
                                    case .failure(let error):
                                        serverMessage = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Label("Sign In", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .disabled(backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || serverEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || serverPassword.isEmpty)
                    }

                    if isServerWorking {
                        ProgressView()
                    }
                    if !serverMessage.isEmpty {
                        Text(serverMessage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Account & Server")
                } footer: {
                    Text("Use a Railway backend URL to enable account-based sync across devices. Without it, Aura keeps using local storage and the existing household code flow.")
                }

                // ── Categories ────────────────────────────────
                Section("Event Categories") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(store.categories.prefix(6))) { c in
                                HStack(spacing: 5) {
                                    Image(systemName: c.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(c.color)
                                    Text(c.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(c.color.opacity(0.12), in: Capsule())
                            }
                            if store.categories.count > 6 {
                                Text("+\(store.categories.count - 6)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                        }
                    }

                    Button {
                        showCategoryManager = true
                    } label: {
                        HStack {
                            Label("Manage Categories", systemImage: "slider.horizontal.3")
                            Spacer()
                            Text("\(store.categories.count)")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button { showAdd = true } label: {
                        Label("Add Category", systemImage: "plus.circle.fill")
                            .foregroundColor(AuraThemePalette.current.accentStart)
                    }
                }

                // ── Widget Theme ─────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        // current theme name
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Active Theme")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(selectedTheme?.name ?? "Indigo Night")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Spacer()
                            // mini gradient swatch
                            if let t = selectedTheme {
                                LinearGradient(
                                    colors: [Color(hex: t.c1), Color(hex: t.c2)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                                .frame(width: 44, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        // circle row
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(allThemes) { t in
                                    Button {
                                        AuraHaptics.tap(.medium)
                                        selectedThemeId = t.id
                                        saveThemeSelection(t)
                                    } label: {
                                        ZStack {
                                            LinearGradient(
                                                colors: [Color(hex: t.c1), Color(hex: t.c2)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            )
                                            .frame(width: 44, height: 44)
                                            .clipShape(Circle())
                                            if t.id == selectedThemeId {
                                                Circle()
                                                    .stroke(Color.white, lineWidth: 3)
                                                    .frame(width: 44, height: 44)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                // + button
                                Button { showGradientBuilder = true } label: {
                                    ZStack {
                                        Circle()
                                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                                            .foregroundColor(.secondary.opacity(0.5))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "plus")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Widget Theme")
                } footer: {
                    Text("Tap + to build a custom gradient from your own colours.")
                }

                // ── Notifications ─────────────────────────────
                Section("Notifications") {
                    Toggle("Themed In-App Banner", isOn: $enableInAppBanner)
                    Button {
                        NotificationCenter.default.post(
                            name: .auraInAppBanner,
                            object: nil,
                            userInfo: [
                                "title": "Preview Notification",
                                "message": "This is how your in-app banner looks with the current theme."
                            ]
                        )
                    } label: {
                        Label("Preview In-App Banner", systemImage: "rectangle.and.text.magnifyingglass")
                    }
                    Button {
                        if let u = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(u)
                        }
                    } label: {
                        Label("Open Notification Settings", systemImage: "bell.badge")
                            .foregroundColor(.primary)
                    }
                }

                // ── Shared ─────────────────────────────
                Section("Shared") {
                    if sharedBySender.isEmpty {
                        Text("No shared events yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(sharedBySender, id: \.0) { sender, count in
                            HStack {
                                Label(sender, systemImage: "person.2.fill")
                                Spacer()
                                Text("\(count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Button {
                        showSharedManager = true
                    } label: {
                        Label("Manage Shared Events", systemImage: "person.2.wave.2")
                    }
                    Button {
                        showSharedActivityLog = true
                    } label: {
                        Label("Shared Activity Log", systemImage: "clock.arrow.circlepath")
                    }
                }

                // ── Household Sync ─────────────────────────────
                Section {
                    TextField("Household Code", text: $householdCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if store.hasServerSession {
                        TextField("Server household name", text: $householdNameDraft)
                    }

                    HStack {
                        Label("Status", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text(store.syncStatus)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    Button {
                        if store.hasServerSession {
                            isServerWorking = true
                            serverMessage = ""
                            Task {
                                let result = await store.createServerHousehold(name: householdNameDraft)
                                await MainActor.run {
                                    isServerWorking = false
                                    switch result {
                                    case .success(let code):
                                        householdCode = code
                                        backendStoredHouseholdName = householdNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                        serverMessage = "Server household created with code \(code)."
                                    case .failure(let error):
                                        serverMessage = error.localizedDescription
                                    }
                                }
                            }
                        } else {
                            if householdCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                householdCode = String(UUID().uuidString.prefix(8)).lowercased()
                            }
                            store.updateHouseholdCode(householdCode)
                            store.forceSyncNow()
                        }
                    } label: {
                        Label(store.hasServerSession ? "Create Server Household" : "Link / Create Household", systemImage: "person.3.sequence.fill")
                    }

                    if store.hasServerSession {
                        Button {
                            isServerWorking = true
                            serverMessage = ""
                            Task {
                                let result = await store.joinServerHousehold(code: householdCode)
                                await MainActor.run {
                                    isServerWorking = false
                                    switch result {
                                    case .success:
                                        serverMessage = "Joined server household successfully."
                                    case .failure(let error):
                                        serverMessage = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Label("Join Server Household", systemImage: "person.2.badge.plus")
                        }
                        .disabled(householdCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if !backendStoredHouseholdName.isEmpty || !store.serverHouseholdName.isEmpty {
                            LabeledContent("Current household", value: store.serverHouseholdName.isEmpty ? backendStoredHouseholdName : store.serverHouseholdName)
                        }
                    }

                    Button {
                        store.forceSyncNow()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.clockwise")
                    }
                    .disabled(householdCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Household Sync")
                } footer: {
                    Text(store.hasServerSession ? "Invite family by sharing the household code after they create or sign in to an account." : "Use the same household code on each family phone to sync Lists and Activities.")
                }

                // ── Profile ─────────────────────────────
                Section {
                    TextField("Display name (for sharing)", text: $profileDisplayName)
                } header: {
                    Text("Profile")
                } footer: {
                    Text("No server account required. Your display name is stored only on this device.")
                }

                // ── About ─────────────────────────────────────
                Section("About") {
                    LabeledContent("App",     value: "Aura")
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build",   value: "SwiftUI · iOS 16+")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAdd) {
                AddCategoryView(isPresented: $showAdd).environmentObject(store)
            }
            .sheet(isPresented: $showCategoryManager) {
                CategoryManagerView().environmentObject(store)
            }
            .sheet(isPresented: $showSharedManager) {
                SharedEventsManagerView().environmentObject(store)
            }
            .sheet(isPresented: $showSharedActivityLog) {
                SharedActivityLogView().environmentObject(store)
            }
            .sheet(isPresented: $showCatSound) {
                SoundPickerSheet(
                    isPresented: $showCatSound,
                    currentSound: catSoundVal,
                    onSelect: { newSound in
                        if let catId = editSoundCatId,
                           let idx = store.categories.firstIndex(where: { $0.id == catId }) {
                            store.categories[idx].sound = newSound == .systemDefault ? nil : newSound
                            store.saveCats()
                        }
                        catSoundVal    = newSound
                        editSoundCatId = nil
                    }
                )
            }
            .sheet(isPresented: $showGradientBuilder) {
                CustomGradientBuilderView(isPresented: $showGradientBuilder) { theme in
                    customThemes.append(theme)
                    selectedThemeId = theme.id
                    saveThemeSelection(theme)
                    saveCustomThemes()
                }
            }
            .sheet(isPresented: $showAddMember) {
                AddMemberView(isPresented: $showAddMember).environmentObject(store)
            }
            .onAppear {
                stepCustomNames = Set(dailyStepSharedWithNames)
                serverEmail = backendAccountEmail
                serverDisplayName = profileDisplayName
                householdNameDraft = backendStoredHouseholdName.isEmpty ? "My Family" : backendStoredHouseholdName
                Task {
                    await store.refreshServerContext()
                    await MainActor.run {
                        serverDisplayName = profileDisplayName
                    }
                }
                loadCustomThemes()
                if let d = widgetThemeJSON.data(using: .utf8),
                   let t = try? JSONDecoder().decode(WidgetGradientTheme.self, from: d) {
                    selectedThemeId = t.id
                }
            }
        }
    }

    func saveThemeSelection(_ t: WidgetGradientTheme) {
        if let d = try? JSONEncoder().encode(t) {
            let s = String(data: d, encoding: .utf8) ?? ""
            widgetThemeJSON = s
            UserDefaults(suiteName: "group.com.personal.aura")?.set(s, forKey: "widgetThemeJSON")
        }
    }
    func saveCustomThemes() {
        if let d = try? JSONEncoder().encode(customThemes) {
            UserDefaults(suiteName: "group.com.personal.aura")?.set(d, forKey: "aura.customGradientThemes")
        }
    }
    func loadCustomThemes() {
        if let d = UserDefaults(suiteName: "group.com.personal.aura")?.data(forKey: "aura.customGradientThemes"),
           let v = try? JSONDecoder().decode([WidgetGradientTheme].self, from: d) {
            customThemes = v
        }
    }
}

// MARK: - Custom Gradient Builder

struct CustomGradientBuilderView: View {
    @Binding var isPresented: Bool
    var onSave: (WidgetGradientTheme) -> Void

    @State private var name  = ""
    @State private var c1 = Color(hex: "1E1B4B")
    @State private var c2 = Color(hex: "4C1D95")
    @State private var n1 = Color(hex: "6366F1")
    @State private var n2 = Color(hex: "A78BFA")

    var body: some View {
        NavigationView {
            Form {
                Section {
                    // live preview strip
                    LinearGradient(
                        colors: [c1, c2],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: { Text("Preview") }

                Section {
                    TextField("e.g. My Purple Dream", text: $name)
                } header: { Text("Theme Name") }

                Section {
                    ColorPicker("Background — Top colour",    selection: $c1)
                    ColorPicker("Background — Bottom colour", selection: $c2)
                } header: { Text("Background Gradient") }

                Section {
                    ColorPicker("Number — Top colour",    selection: $n1)
                    ColorPicker("Number — Bottom colour", selection: $n2)
                } header: { Text("Countdown Number Gradient") }
                footer: {
                    Text("These two colours form the gradient on the large countdown number in the widget.")
                }
            }
            .navigationTitle("New Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        AuraHaptics.success()
                        let theme = WidgetGradientTheme(
                            name: name.isEmpty ? "Custom" : name,
                            c1: c1.toHex(), c2: c2.toHex(),
                            n1: n1.toHex(), n2: n2.toHex()
                        )
                        onSave(theme)
                        isPresented = false
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Category Manager

struct CategoryManagerView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    @State private var q = ""
    @State private var editSoundCatId: UUID? = nil
    @State private var catSoundVal: AppSound = .systemDefault
    @State private var showCatSound = false
    @State private var editCategory: EventCategory? = nil

    var filtered: [EventCategory] {
        q.isEmpty ? store.categories : store.categories.filter {
            $0.name.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filtered) { c in
                    HStack(spacing: 12) {
                        Image(systemName: c.icon)
                            .font(.system(size: 15))
                            .foregroundColor(c.color)
                            .frame(width: 30, height: 30)
                            .background(c.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name)
                                .font(.system(size: 15, weight: .semibold))
                            Text(c.isCustom ? "Custom" : "Default")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            editCategory = c
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        Button {
                            editSoundCatId = c.id
                            catSoundVal = c.sound ?? .systemDefault
                            showCatSound = true
                        } label: {
                            Label(catSoundValFor(c).rawValue, systemImage: catSoundValFor(c).icon)
                                .font(.system(size: 12, weight: .semibold))
                                .labelStyle(.iconOnly)
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.deleteCategory(id: c.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .searchable(text: $q, prompt: "Search categories")
            .navigationTitle("Manage Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCatSound) {
                SoundPickerSheet(
                    isPresented: $showCatSound,
                    currentSound: catSoundVal,
                    onSelect: { newSound in
                        if let id = editSoundCatId,
                           let idx = store.categories.firstIndex(where: { $0.id == id }) {
                            store.categories[idx].sound = newSound == .systemDefault ? nil : newSound
                            store.saveCats()
                        }
                        editSoundCatId = nil
                    }
                )
            }
            .sheet(item: $editCategory) { c in
                EditCategoryView(category: c).environmentObject(store)
            }
        }
    }

    private func catSoundValFor(_ c: EventCategory) -> AppSound {
        c.sound ?? .systemDefault
    }
}

struct EditCategoryView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss

    let category: EventCategory
    @State private var name = ""
    @State private var color = Color(hex: "6366F1")
    @State private var icon = "tag.fill"
    @State private var sound = AppSound.systemDefault
    @State private var showSoundPicker = false

    let icons = [
        "tag.fill", "star.fill", "heart.fill", "bolt.fill", "flame.fill",
        "music.note", "briefcase.fill", "book.fill", "person.fill", "car.fill",
        "house.fill", "airplane", "stethoscope", "cross.fill", "leaf.fill",
        "camera.fill", "fork.knife", "figure.walk", "dumbbell.fill", "trophy.fill",
        "bell.fill", "gift.fill", "cart.fill", "pawprint.fill", "graduationcap.fill",
        "building.2.fill", "house.heart.fill", "book.closed.fill", "figure.and.child.holdinghands"
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                }
                Section("Colour") {
                    ColorPicker("Pick colour", selection: $color)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(icons, id: \.self) { i in
                            Image(systemName: i)
                                .font(.system(size: 20))
                                .foregroundColor(icon == i ? .white : color)
                                .frame(width: 44, height: 44)
                                .background(icon == i ? color : color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { icon = i }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Alert Sound") {
                    Button { showSoundPicker = true } label: {
                        HStack {
                            Label(sound.rawValue, systemImage: sound.icon)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSoundPicker) {
                SoundPickerSheet(
                    isPresented: $showSoundPicker,
                    currentSound: sound,
                    onSelect: { sound = $0 }
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updated = category
                        updated.name = name
                        updated.colorHex = color.toHex()
                        updated.icon = icon
                        updated.sound = sound == .systemDefault ? nil : sound
                        store.updateCategory(updated)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = category.name
                color = category.color
                icon = category.icon
                sound = category.sound ?? .systemDefault
            }
        }
    }
}

// MARK: - Shared Events Manager

struct SharedEventsManagerView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss

    var grouped: [(sender: String, events: [CalendarEvent])] {
        let items = store.events.filter { $0.sharedBy != nil }
        let g = Dictionary(grouping: items) { $0.sharedBy ?? "Unknown" }
        return g
            .map { (sender: $0.key, events: $0.value.sorted { $0.startDate < $1.startDate }) }
            .sorted { $0.sender.localizedCaseInsensitiveCompare($1.sender) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            List {
                if store.isBootstrapping {
                    SharedSkeletonListView()
                        .transition(.opacity)
                } else if grouped.isEmpty {
                    Text("No shared events")
                        .foregroundColor(.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                ForEach(grouped, id: \.sender) { group in
                    Section {
                        ForEach(group.events) { e in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(e.title)
                                        .font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Menu {
                                        Button("View") {
                                            AuraHaptics.tap(.light)
                                            store.setSharePermission(id: e.id, permission: .view)
                                        }
                                        Button("Edit") {
                                            AuraHaptics.success()
                                            store.setSharePermission(id: e.id, permission: .edit)
                                        }
                                        Button(role: .destructive) {
                                            AuraHaptics.warning()
                                            store.revokeSharedEvent(id: e.id)
                                        } label: {
                                            Label("Revoke", systemImage: "trash")
                                        }
                                    } label: {
                                        Text(e.sharePermission.rawValue)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AuraThemePalette.current.accentStart.opacity(0.12), in: Capsule())
                                    }
                                }
                                Text(eventDateLabel(e.startDate))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    } header: {
                        Text(group.sender)
                    }
                }
            }
            .animation(AuraMotion.smooth, value: store.isBootstrapping)
            .animation(AuraMotion.smooth, value: grouped.isEmpty)
            .navigationTitle("Shared Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func eventDateLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

struct SharedActivityLogView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                if store.isBootstrapping {
                    SharedSkeletonListView()
                        .transition(.opacity)
                } else if store.sharedActivity.isEmpty {
                    Text("No shared activity yet")
                        .foregroundColor(.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    ForEach(store.sharedActivity) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.action.rawValue)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AuraThemePalette.current.accentStart)
                                Spacer()
                                Text(dateLabel(entry.timestamp))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            Text(entry.eventTitle)
                                .font(.system(size: 15, weight: .semibold))
                            Text("By: \(entry.sender)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(entry.details)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .animation(AuraMotion.smooth, value: store.isBootstrapping)
            .animation(AuraMotion.smooth, value: store.sharedActivity.isEmpty)
            .navigationTitle("Shared Activity Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func dateLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

// MARK: - Add Category

struct AddCategoryView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var name  = ""
    @State private var color = Color(hex: "6366F1")
    @State private var icon  = "tag.fill"
    @State private var sound = AppSound.systemDefault
    @State private var showSoundPicker = false

    let icons = [
        "tag.fill",      "star.fill",      "heart.fill",      "bolt.fill",        "flame.fill",
        "music.note",    "briefcase.fill",  "book.fill",       "person.fill",      "car.fill",
        "house.fill",    "airplane",        "stethoscope",     "cross.fill",       "leaf.fill",
        "camera.fill",   "fork.knife",      "figure.walk",     "dumbbell.fill",    "trophy.fill",
        "bell.fill",     "gift.fill",       "cart.fill",       "pawprint.fill",    "graduationcap.fill",
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                }

                Section("Colour") {
                    ColorPicker("Pick colour", selection: $color)
                }

                Section("Icon") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 5),
                        spacing: 10
                    ) {
                        ForEach(icons, id: \.self) { i in
                            Image(systemName: i).font(.system(size: 20))
                                .foregroundColor(icon == i ? .white : color)
                                .frame(width: 44, height: 44)
                                .background(icon == i ? color : color.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .onTapGesture {
                                    AuraHaptics.tap(.light)
                                    icon = i
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Alert Sound") {
                    Button { showSoundPicker = true } label: {
                        HStack {
                            Label(sound.rawValue, systemImage: sound.icon)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Preview") {
                    HStack(spacing: 12) {
                        Image(systemName: icon).font(.system(size: 15))
                            .foregroundColor(color)
                            .frame(width: 30, height: 30)
                            .background(color.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 8))
                        Text(name.isEmpty ? "Category name…" : name)
                            .foregroundColor(name.isEmpty ? .secondary : .primary)
                    }
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSoundPicker) {
                SoundPickerSheet(
                    isPresented: $showSoundPicker,
                    currentSound: sound,
                    onSelect: { sound = $0 }
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        AuraHaptics.success()
                        store.addCategory(.init(
                            name:     name,
                            colorHex: color.toHex(),
                            icon:     icon,
                            isCustom: true,
                            sound:    sound == .systemDefault ? nil : sound
                        ))
                        isPresented = false
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.bold)
                }
            }
        }
    }
}

struct SharedSkeletonListView: View {
    var body: some View {
        ForEach(0..<4, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 58)
                .redacted(reason: .placeholder)
        }
    }
}
