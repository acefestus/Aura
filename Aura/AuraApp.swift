// ============================================================
//  Aura — Premium Calendar & Reminder App
//  Minimum: iOS 16  |  No third-party dependencies
//  Sideload via AltStore, Sideloadly, or direct Xcode install
// ============================================================

import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

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
                .onOpenURL { url in
                    shareManager.handleIncomingURL(url)
                }
        }
    }
}

struct ImportPresetItem: Identifiable {
    let id = UUID()
    let preset: EventDraftPreset
}

struct AuraAppShellView: View {
    @EnvironmentObject var store: EventStore
    @AppStorage("aura.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("aura.allowOfflineMode") private var allowOfflineMode = false
    @State private var showSplash = true
    @ObservedObject private var alarmManager = AlarmFiringManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var importQueue: [AuraImportedEventDraft] = []
    @State private var currentImportItem: ImportPresetItem?

    private var readyForImports: Bool {
        !showSplash && hasSeenOnboarding && (store.hasServerSession || allowOfflineMode)
    }

    private func checkPendingImports() {
        guard currentImportItem == nil, importQueue.isEmpty else { return }
        let drafts = SharedImportInbox.takeAll()
        guard !drafts.isEmpty else { return }
        importQueue = drafts
        presentNextQueuedImport()
    }

    private func presentNextQueuedImport() {
        guard !importQueue.isEmpty else { return }
        let draft = importQueue.removeFirst()
        var preset = EventDraftPreset.defaultForActiveMember(in: store)
        preset.title = draft.title
        preset.notes = draft.sourceLabel.isEmpty ? draft.notes : "Imported from \(draft.sourceLabel)\n\n\(draft.notes)"
        preset.location = draft.location
        preset.start = draft.startDate
        preset.end = draft.endDate
        preset.categoryId = store.categories.first(where: { $0.name == "Personal" })?.id ?? preset.categoryId
        currentImportItem = ImportPresetItem(preset: preset)
    }

    private var snoozeMinutes: Int {
        let saved = UserDefaults.standard.integer(forKey: "reminderSnoozeMinutes")
        return saved == 0 ? 10 : saved
    }
    private var snoozeEnabled: Bool {
        let actionable = UserDefaults.standard.object(forKey: "enableActionableReminders") == nil
            ? true : UserDefaults.standard.bool(forKey: "enableActionableReminders")
        let snooze = UserDefaults.standard.object(forKey: "enableReminderSnooze") == nil
            ? true : UserDefaults.standard.bool(forKey: "enableReminderSnooze")
        return actionable && snooze
    }

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
            } else if (!store.hasServerSession || !store.hasServerGroups) && !allowOfflineMode {
                // A session with zero groups still needs AuraAuthGatewayView --
                // it's the same view, but once hasServerSession is true it
                // switches to showing "Create Group" / "Join Group" instead of
                // the sign-in form. Previously this only checked hasServerSession,
                // so a brand-new account landed straight on ContentView with no
                // group and no way to create/join one (that section of
                // AuraAuthGatewayView existed but was never reachable).
                AuraAuthGatewayView()
                    .transition(.opacity)
            } else {
                ContentView()
                    .transition(.opacity)
            }
        }
        .animation(AuraMotion.smooth, value: showSplash)
        // Text follows the user's size setting; beyond this the fixed-size
        // badges and circles around it stop fitting.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onAppear {
            // Safety net: the .task below has been seen to never finish (the
            // splash stayed up indefinitely), so never let it outlive 2.5s.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if showSplash {
                    withAnimation(AuraMotion.smooth) { showSplash = false }
                }
            }
        }
        .task {
            guard showSplash else { return }
            #if DEBUG
            let splashDelayNs: UInt64 = 250_000_000
            #else
            let splashDelayNs: UInt64 = 1_100_000_000
            #endif
            try? await Task.sleep(nanoseconds: splashDelayNs)
            withAnimation(AuraMotion.smooth) {
                showSplash = false
            }
        }
        .fullScreenCover(item: $alarmManager.firing) { alarm in
            AlarmFiringView(
                alarm: alarm,
                onSnooze: { alarmManager.snooze(minutes: snoozeMinutes) },
                onDismiss: { alarmManager.dismiss() },
                snoozeMinutes: snoozeMinutes,
                snoozeEnabled: snoozeEnabled
            )
        }
        .sheet(item: $currentImportItem) { item in
            CreateEventView(
                isPresented: Binding(get: { true }, set: { _ in currentImportItem = nil }),
                preset: item.preset
            )
            .environmentObject(store)
        }
        .onChange(of: currentImportItem?.id) { newValue in
            if newValue == nil { presentNextQueuedImport() }
        }
        .onChange(of: readyForImports) { ready in
            if ready { checkPendingImports() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && readyForImports {
                checkPendingImports()
                // Pulling right when the app comes back to the foreground
                // means whatever another group member added while this
                // device was away shows up immediately, instead of waiting
                // for the next periodic poll (up to ~6s later).
                store.forceSyncNow()
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
                Image("AppIconGraphic")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                Text("Aurenda")
                    .auraFont(size: 40, weight: .black, design: .rounded)
                    .foregroundColor(.white)
                Text("Shared Life, Organized")
                    .auraFont(size: 14, weight: .semibold)
                    .foregroundColor(.white.opacity(0.85))
                Text("Multi-Group Planner + Personal Command Center")
                    .auraFont(size: 12, weight: .medium)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

struct AuraHeroGroupImage: View {
    let fallbackIcon: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AuraThemePalette.current.backgroundStart.opacity(0.95), AuraThemePalette.current.backgroundEnd.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AuraThemePalette.current.accentStart.opacity(0.28))
                .frame(width: 220, height: 220)
                .blur(radius: 22)
                .offset(x: -92, y: -78)

            Circle()
                .fill(AuraThemePalette.current.accentEnd.opacity(0.22))
                .frame(width: 200, height: 200)
                .blur(radius: 26)
                .offset(x: 116, y: 82)

            fannedCard(rotation: -14, offsetX: -34)
            fannedCard(rotation: 14, offsetX: 34)

            // Center hero card carries the concept-specific glyph.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 44, height: 7)
                    Spacer()
                }
                HStack {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                        .frame(width: 64, height: 7)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle().fill(Color.black.opacity(0.4)).frame(width: 30, height: 30)
                        Image(systemName: fallbackIcon)
                            .auraFont(size: 14, weight: .bold)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(14)
            .frame(width: 128, height: 104)
            .background(
                LinearGradient(
                    colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: AuraThemePalette.current.accentStart.opacity(0.5), radius: 14, y: 6)
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func fannedCard(rotation: Double, offsetX: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(0.55))
                .frame(width: 30, height: 6)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(0.32))
                .frame(width: 44, height: 6)
            Spacer()
        }
        .padding(12)
        .frame(width: 112, height: 92)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.26), lineWidth: 1))
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .offset(x: offsetX, y: 6)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 5)
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
                        title: "One Personal Command Center",
                        subtitle: "See your calendar, tasks, plans, and routines across every group in one clean personal layer.",
                        fallbackIcon: "person.crop.circle.badge.checkmark",
                        badge: "Personal Layer"
                    ).tag(0)

                    onboardingCard(
                        title: "Private Group Workspaces",
                        subtitle: "Family, roommates, church, travel, study, or custom groups stay isolated by design.",
                        fallbackIcon: "square.stack.3d.up.fill",
                        badge: "Boundary Control"
                    ).tag(1)

                    onboardingCard(
                        title: "Plan Together, Resolve Faster",
                        subtitle: "Create or join groups, assign roles, and resolve scheduling conflicts before they become chaos.",
                        fallbackIcon: "bolt.horizontal.circle.fill",
                        badge: "Conflict Smart"
                    ).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxHeight: 520)

                HStack(spacing: 10) {
                    Button(page == 2 ? "Get Started" : "Next") {
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

    private func onboardingCard(title: String, subtitle: String, fallbackIcon: String, badge: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AuraHeroGroupImage(fallbackIcon: fallbackIcon)
                .frame(height: 260)

            Text(badge.uppercased())
                .auraFont(size: 10, weight: .bold, design: .rounded)
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.12), in: Capsule())

            Text(title)
                .auraFont(size: 28, weight: .black, design: .rounded)
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .auraFont(size: 15, weight: .medium)
                .foregroundColor(.white.opacity(0.86))
                .lineLimit(3)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}
