import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

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
    @State private var showGroupMembers = false
    @State private var showGroupsHub = false
    @State private var eventDraftPreset: EventDraftPreset? = nil
    @AppStorage("colorScheme") private var scheme = "system"
    @AppStorage("widgetThemeJSON") private var widgetThemeJSON = ""

    var preferredScheme: ColorScheme? {
        scheme == "light" ? .light : scheme == "dark" ? .dark : nil
    }
    var palette: AuraThemePalette { .from(themeJSON: widgetThemeJSON) }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                HomeView(showCreate: $showCreate, eventDraftPreset: $eventDraftPreset)
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
                PersonalHubView()
                    .id("personal-\(widgetThemeJSON)")
                    .tabItem { Label("Personal", systemImage: "person.crop.circle") }.tag(4)
                SettingsView()
                    .id("settings-\(widgetThemeJSON)")
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(5)
            }
            .tint(palette.accentStart)

            VStack {
                if let b = bannerPayload {
                    AuraInAppBannerView(payload: b, palette: palette)
                        .padding(.top, 8)
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if store.hasServerSession && store.hasServerGroups {
                    HStack {
                        Button {
                            showGroupsHub = true
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(store.activeServerGroupName)
                                    .lineLimit(1)
                                if store.serverGroups.count > 1 {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .bold))
                                }
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                            .foregroundStyle(.white)
                            .shadow(color: Color(hex: "6366F1").opacity(0.45), radius: 10, y: 4)
                        }
                        Spacer()
                        Button {
                            showGroupMembers = true
                        } label: {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.28), in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, bannerPayload == nil ? 8 : 0)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .animation(AuraMotion.banner, value: bannerPayload)
            .sheet(isPresented: $showGroupMembers) {
                GroupMembersView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showGroupsHub) {
                GroupsHubView(isPresented: $showGroupsHub)
                    .environmentObject(store)
            }

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
        .sheet(isPresented: $showCreate, onDismiss: {
            eventDraftPreset = nil
        }) {
            CreateEventView(isPresented: $showCreate, preset: eventDraftPreset).environmentObject(store)
        }
        .sheet(isPresented: $showAddList) {
            AddGroupListView(isPresented: $showAddList).environmentObject(store)
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
            Button("Schedule Event") {
                eventDraftPreset = .defaultForActiveMember(in: store)
                showCreate = true
            }
            Button("Log Activity") { showAddActivity = true }
            Button("Track Activity") { showStartLiveActivity = true }
            Button("Add List Item") { showQuickGrocery = true }
            Button("Create Shared List") { showAddList = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Shared Aurenda Data",
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
        case 5:
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
    @Binding var eventDraftPreset: EventDraftPreset?
    @State private var showLogActivity = false
    @State private var showStartLiveActivity = false
    @State private var showQuickAddItem = false
    @State private var showQuickEventTemplates = false
    @State private var showRoutineTemplates = false
    @State private var showWeekPlanner = false
    @State private var showOnlyShared = true
    @State private var editingActivity: GroupActivity? = nil

    var todayEventsCount: Int {
        store.events(for: Date()).count
    }

    var pendingShoppingItems: Int {
        (showOnlyShared ? store.visibleGroupLists : store.groupLists)
            .flatMap { $0.items }
            .filter { !$0.isDone }
            .count
    }

    var recentActivities: [GroupActivity] {
        Array((showOnlyShared ? store.visibleGroupActivities : store.groupActivities).prefix(3))
    }

    var todayEvents: [CalendarEvent] {
        store.events(for: Date()).sorted { $0.startDate < $1.startDate }
    }

    var upcomingEvents: [CalendarEvent] {
        let source = showOnlyShared ? store.visibleEvents : store.events
        return source
            .filter { $0.startDate > Date() && !Calendar.current.isDateInToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)
            .map { $0 }
    }

    var hasSyncIssue: Bool {
        let lower = store.syncStatus.lowercased()
        return lower.contains("failed") || lower.contains("unavailable") || lower.contains("expired")
    }

    /// A calmer, Home-specific rendering of syncStatus -- "Sync disabled" reads as an
    /// error even though it just means "not in a shared group yet", which is a normal
    /// state, not a problem. Other screens still show the precise underlying status.
    var homeStatusLabel: String {
        store.syncStatus == "Sync disabled" ? "Personal mode" : store.syncStatus
    }

    var workloadByMember: [(member: GroupMember, count: Int)] {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let source = showOnlyShared ? store.visibleEvents : store.events
        return store.members.map { member in
            let count = source.filter { event in
                event.startDate >= Date() &&
                event.startDate <= horizon &&
                event.assignedMemberIds.contains(member.id)
            }.count
            return (member, count)
        }
    }

    var topLoadCount: Int {
        workloadByMember.map(\.count).max() ?? 0
    }

    var leastLoadCount: Int {
        workloadByMember.map(\.count).min() ?? 0
    }

    var activeStreakDays: Int {
        let cal = Calendar.current
        let activityDates: [Date] = (showOnlyShared ? store.visibleGroupActivities : store.groupActivities).map { $0.date }
        let activeDays = Set(activityDates.map { cal.startOfDay(for: $0) })
        var streak = 0
        for offset in 0..<30 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())) else { break }
            if activeDays.contains(day) {
                streak += 1
            } else if offset == 0 {
                continue
            } else {
                break
            }
        }
        return streak
    }

    var balanceScore: Int {
        guard topLoadCount > 0 else { return 100 }
        let spread = topLoadCount - leastLoadCount
        let ratio = Double(spread) / Double(topLoadCount)
        return max(0, Int((1 - ratio) * 100))
    }

    var proactiveRecommendations: [String] {
        var notes: [String] = []
        if todayEventsCount == 0 {
            notes.append("No events today. Add a focus block now to keep the family rhythm consistent.")
        }
        if pendingShoppingItems >= 8 {
            notes.append("Shopping backlog is high. Use Weekly Grocery Run template to clear items in one trip.")
        }
        if topLoadCount >= 4 && topLoadCount - leastLoadCount >= 3,
           let busiest = workloadByMember.max(by: { $0.count < $1.count })?.member.name {
            notes.append("\(busiest) has the heaviest schedule this week. Reassign one event to balance workload.")
        }
        if upcomingEvents.count <= 1 {
            notes.append("Light upcoming calendar. Seed next week with 2 routine templates to avoid last-minute rush.")
        }
        if activeStreakDays >= 5 {
            notes.append("Great momentum: \(activeStreakDays)-day family activity streak. Keep it going tomorrow.")
        }
        if notes.isEmpty {
            notes.append("Schedule looks healthy. Review Friday and weekend plans early to stay ahead.")
        }
        return Array(notes.prefix(3))
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Good Night"
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
            AuraAtmosphericBackground()
            ScrollView {
                VStack(spacing: 14) {
                    HomeHeroCard(
                        title: "\(greeting), \(store.activeProfileName)",
                        subtitle: "\(todayEventsCount) events today · \(pendingShoppingItems) list items pending",
                        detail: homeStatusLabel
                    ) {
                        Task { await store.refreshHomeDashboard() }
                    }

                    if hasSyncIssue {
                        HomeSectionCard(title: "Needs Attention") {
                            Label(store.syncStatus, systemImage: "wifi.exclamationmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                            Text("Pull to refresh on Home or tap Refresh to reconnect and pull the latest workspace data.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    ChangeRequestsCard()

                    if let session = store.activeActivitySession {
                        HomeSectionCard(title: "Currently Tracking") {
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
                        if store.isBootstrapping {
                            HomeLoadingRows()
                        } else if todayEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "moon.stars")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AuraThemePalette.current.accentStart)
                                    Text("Nothing planned for today")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                Text("Use Schedule Event to add your next shared moment.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Button("Add First Event") {
                                    eventDraftPreset = .defaultForActiveMember(in: store)
                                    showCreate = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AuraThemePalette.current.accentStart)
                            }
                        } else {
                            VStack(spacing: 8) {
                                ForEach(todayEvents.prefix(4)) { e in
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

                    HomeSectionCard(title: "Upcoming") {
                        if store.isBootstrapping {
                            HomeLoadingRows()
                        } else if upcomingEvents.isEmpty {
                            Text("No upcoming events after today.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(upcomingEvents) { e in
                                    HStack {
                                        Image(systemName: "calendar")
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(e.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .lineLimit(1)
                                            Text(dayAndTimeLabel(e))
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        HomeQuickActionButton(label: "Schedule Event", icon: "calendar.badge.plus", prominent: true) {
                            AuraHaptics.tap(.light)
                            showQuickEventTemplates = true
                        }
                        HomeQuickActionButton(label: "Log Activity", icon: "figure.walk") {
                            AuraHaptics.tap(.light)
                            showLogActivity = true
                        }
                    }

                    HStack(spacing: 10) {
                        HomeQuickActionButton(label: "Add List Item", icon: "cart.badge.plus") {
                            AuraHaptics.tap(.light)
                            showQuickAddItem = true
                        }
                        HomeQuickActionButton(label: "Track Activity", icon: "play.circle.fill") {
                            AuraHaptics.tap(.light)
                            showStartLiveActivity = true
                        }
                    }

                    HomeQuickActionButton(label: "Use Routine Template", icon: "wand.and.stars") {
                        AuraHaptics.tap(.medium)
                        showRoutineTemplates = true
                    }

                    HomeQuickActionButton(label: "Plan My Week", icon: "calendar.day.timeline.leading") {
                        AuraHaptics.tap(.medium)
                        showWeekPlanner = true
                    }

                    HomeSectionCard(title: "Group Insights") {
                        HStack(spacing: 8) {
                            HomeInsightBadge(title: "Balance", value: "\(balanceScore)%")
                            HomeInsightBadge(title: "Streak", value: "\(activeStreakDays)d")
                            HomeInsightBadge(title: "Next 7d", value: "\(workloadByMember.map(\.count).reduce(0, +))")
                        }

                        if workloadByMember.isEmpty {
                            Text("Add members to see workload insights.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(workloadByMember, id: \.member.id) { item in
                                    HomeMemberLoadRow(
                                        name: item.member.name,
                                        color: item.member.color,
                                        count: item.count,
                                        maxCount: max(1, topLoadCount)
                                    )
                                }
                            }
                        }

                        Divider().padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Proactive Recommendations")
                                .font(.system(size: 13, weight: .bold))
                            ForEach(Array(proactiveRecommendations.enumerated()), id: \.offset) { _, note in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AuraThemePalette.current.accentStart)
                                        .padding(.top, 2)
                                    Text(note)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    HomeSectionCard(title: "Recent Group Activities") {
                        if store.isBootstrapping {
                            HomeLoadingRows()
                        } else if recentActivities.isEmpty {
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("DISPLAY FILTER")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show only items shared with me")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(showOnlyShared ? "Hiding items outside your access." : "Showing everything in this workspace.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $showOnlyShared)
                                .labelsHidden()
                                .tint(AuraThemePalette.current.accentStart)
                        }
                        if !store.members.isEmpty {
                            Divider()
                            HStack {
                                Text("Assign new items as")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Picker("Active Member", selection: Binding(
                                    get: { store.activeMember?.id },
                                    set: { store.setActiveMember(id: $0) }
                                )) {
                                    Text("None").tag(Optional<UUID>.none)
                                    ForEach(store.members) { member in
                                        Text(member.name).tag(Optional(member.id))
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                    .padding(AuraDesignTokens.Spacing.sm)
                    .opacity(0.85)
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            .refreshable {
                await store.refreshHomeDashboard()
            }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Home")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.refreshHomeDashboard() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
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
        .sheet(isPresented: $showWeekPlanner) {
            WeekPlanningAssistantSheet(isPresented: $showWeekPlanner)
                .environmentObject(store)
        }
        .confirmationDialog("Schedule Event", isPresented: $showQuickEventTemplates, titleVisibility: .visible) {
            ForEach(HomeEventQuickTemplate.allCases, id: \.self) { template in
                Button(template.label) {
                    eventDraftPreset = .from(template: template, store: store)
                    showCreate = true
                }
            }
            Button("Custom Event") {
                eventDraftPreset = .defaultForActiveMember(in: store)
                showCreate = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Routine Templates", isPresented: $showRoutineTemplates, titleVisibility: .visible) {
            ForEach(RoutineAutomationTemplate.allCases, id: \.self) { template in
                Button(template.label) {
                    eventDraftPreset = template.preset(in: store)
                    showCreate = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func timeLabel(_ e: CalendarEvent) -> String {
        if e.isAllDay { return "All day" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: e.startDate)
    }

    private func activitySubtitle(_ a: GroupActivity) -> String {
        let names = a.participantIds.compactMap { id in
            store.members.first(where: { $0.id == id })?.name
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        return "\(a.durationMinutes)m · \(names.joined(separator: ", ")) · \(f.string(from: a.date))"
    }

    private func dayAndTimeLabel(_ event: CalendarEvent) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = event.isAllDay ? .none : .short
        return event.isAllDay ? "\(f.string(from: event.startDate)) · All day" : f.string(from: event.startDate)
    }
}

struct PersonalHubView: View {
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var shareManager: ShareManager
    @State private var selectedEvent: CalendarEvent? = nil
    @State private var selectedList: GroupList? = nil
    @State private var selectedPlan: GroupPlan? = nil
    @State private var showAddPlan = false
    @State private var statusMessage = ""
    @State private var showStatusMessage = false
    @State private var dismissedConflictIds: Set<String> = []
    @State private var conflictActionLoadingIds: Set<String> = []
    @Namespace private var personalHeroNamespace

    var body: some View {
        NavigationView {
            ZStack {
            AuraAtmosphericBackground()
            ScrollView {
                VStack(spacing: 14) {
                    HomeHeroCard(
                        title: "Personal Command",
                        subtitle: "\(store.personalMasterCalendarItems.count) calendar · \(store.personalTaskItems.count) tasks · \(store.personalConflictItems.count) conflicts",
                        detail: store.syncStatus
                    ) {
                        Task { await store.refreshPersonalLayer() }
                    }

                    HomeSectionCard(title: "Master Calendar") {
                        if store.isLoadingPersonalLayer {
                            HomeLoadingRows()
                        } else if store.personalMasterCalendarItems.isEmpty {
                            Text("No personal calendar items yet.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(store.personalMasterCalendarItems.prefix(5)) { item in
                                    PersonalAggregateRow(item: item, fallbackIcon: "calendar") {
                                        if let event = store.eventFromPayload(item.payload) {
                                            selectedEvent = event
                                        } else {
                                            statusMessage = "Source event not found on this device yet."
                                            showStatusMessage = true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    HomeSectionCard(title: "My Tasks") {
                        if store.isLoadingPersonalLayer {
                            HomeLoadingRows()
                        } else if store.personalTaskItems.isEmpty {
                            Text("No tasks assigned yet.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(store.personalTaskItems.prefix(5)) { item in
                                    PersonalAggregateRow(item: item, fallbackIcon: "checkmark.circle") {
                                        if let list = store.groupListFromPayload(item.payload) {
                                            selectedList = list
                                        } else {
                                            statusMessage = "Source list not found locally yet."
                                            showStatusMessage = true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    HomeSectionCard(title: "My Plans") {
                        Button {
                            showAddPlan = true
                        } label: {
                            Label("New Plan", systemImage: "plus.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.bottom, 2)

                        if store.isLoadingPersonalLayer {
                            HomeLoadingRows()
                        } else if store.personalPlanItems.isEmpty {
                            Text("No plans yet. Tap New Plan to start one.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(store.personalPlanItems.prefix(5)) { item in
                                    PersonalAggregateRow(item: item, fallbackIcon: "list.bullet.rectangle") {
                                        if let plan = store.planFromPayload(item.payload) {
                                            selectedPlan = plan
                                        } else {
                                            statusMessage = "Source plan not found locally yet."
                                            showStatusMessage = true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    HomeSectionCard(title: "My Routines") {
                        if store.isLoadingPersonalLayer {
                            HomeLoadingRows()
                        } else if store.personalRoutineItems.isEmpty {
                            Text("No routines yet.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(store.personalRoutineItems.prefix(5)) { item in
                                    PersonalAggregateRow(item: item, fallbackIcon: "repeat") {
                                        if let event = store.eventFromPayload(item.payload) {
                                            selectedEvent = event
                                        } else {
                                            statusMessage = "Routine source detail opening will expand in the next chunk."
                                            showStatusMessage = true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    HomeSectionCard(title: "Conflicts") {
                        if store.isLoadingPersonalLayer {
                            HomeLoadingRows()
                        } else if store.personalConflictItems.isEmpty {
                            Text("No conflicts detected.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(store.personalConflictItems.filter { !dismissedConflictIds.contains($0.id) }.prefix(8)) { conflict in
                                    HStack {
                                        Text(conflict.severity)
                                            .font(.system(size: 11, weight: .bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(conflictColor(conflict.severity).opacity(0.2), in: Capsule())
                                            .foregroundColor(conflictColor(conflict.severity))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Overlap Detected")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("\(conflict.leftEventTitle ?? "Untitled event") vs \(conflict.rightEventTitle ?? "Untitled event")")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if conflictActionLoadingIds.contains(conflict.id) {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                        Menu {
                                            Button("Fix now") {
                                                Task { await handleConflictAction(conflict, action: "fix") }
                                            }
                                            Button("Suggest slot") {
                                                Task { await handleConflictAction(conflict, action: "suggest") }
                                            }
                                            Button("Accept anyway") {
                                                Task { await handleConflictAction(conflict, action: "accept") }
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.secondary)
                                        }
                                        .disabled(conflictActionLoadingIds.contains(conflict.id))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            if let event = selectedEvent {
                EventDetailView(
                    event: event,
                    heroNamespace: personalHeroNamespace,
                    onClose: { selectedEvent = nil }
                )
                .environmentObject(store)
                .environmentObject(shareManager)
                .zIndex(10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            }
            .navigationTitle("Personal")
            .refreshable {
                await store.refreshPersonalLayer()
            }
            .task {
                if store.hasServerSession && store.personalMasterCalendarItems.isEmpty && !store.isLoadingPersonalLayer {
                    await store.refreshPersonalLayer()
                }
            }
            .sheet(item: $selectedList) { list in
                GroupListDetailView(listId: list.id)
                    .environmentObject(store)
            }
            .sheet(item: $selectedPlan) { plan in
                GroupPlanDetailView(planId: plan.id)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAddPlan) {
                AddGroupPlanView(isPresented: $showAddPlan)
                    .environmentObject(store)
            }
            .alert("Personal Layer", isPresented: $showStatusMessage) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage)
            }
        }
    }

    private func conflictColor(_ severity: String) -> Color {
        switch severity {
        case "Critical":
            return .red
        case "Hard":
            return .orange
        default:
            return .yellow
        }
    }

    private func conflictEventCandidates(_ conflict: AuraRemoteConflictRecord) -> [UUID] {
        [conflict.leftEventId, conflict.rightEventId].compactMap { UUID(uuidString: $0) }
    }

    private func resolveConflictNow(_ conflict: AuraRemoteConflictRecord) -> Bool {
        for id in conflictEventCandidates(conflict) {
            if store.resolveSharedEventConflict(id: id) {
                return true
            }
        }
        return false
    }

    private func suggestedSlotText(_ conflict: AuraRemoteConflictRecord) -> String? {
        for id in conflictEventCandidates(conflict) {
            if let suggestion = store.suggestedConflictStart(for: id) {
                return "Suggested start: \(suggestion.formatted(date: .abbreviated, time: .shortened))"
            }
        }
        return nil
    }

    @MainActor
    private func handleConflictAction(_ conflict: AuraRemoteConflictRecord, action: String) async {
        guard !conflictActionLoadingIds.contains(conflict.id) else { return }
        conflictActionLoadingIds.insert(conflict.id)
        defer { conflictActionLoadingIds.remove(conflict.id) }

        if store.hasServerSession {
            let result = await store.interceptServerConflict(
                action: action,
                leftEventId: conflict.leftEventId,
                rightEventId: conflict.rightEventId,
                preferredEventId: conflict.leftEventId
            )
            switch result {
            case .success(let response):
                if action == "accept" {
                    dismissedConflictIds.insert(conflict.id)
                    statusMessage = "Conflict acknowledged."
                } else if action == "suggest", let suggestionISO = response.suggestionStart, let suggestionDate = ISO8601DateFormatter().date(from: suggestionISO) {
                    let title = response.eventTitle ?? "Event"
                    statusMessage = "\(title): suggested start \(suggestionDate.formatted(date: .abbreviated, time: .shortened))."
                } else if action == "fix" {
                    if
                        let afterISO = response.afterStart ?? response.suggestionStart,
                        let afterDate = ISO8601DateFormatter().date(from: afterISO)
                    {
                        let title = response.eventTitle ?? "Event"
                        store.applyResolvedConflict(response)
                        if let remaining = response.remainingConflicts {
                            statusMessage = "\(title) moved to \(afterDate.formatted(date: .abbreviated, time: .shortened)). Remaining overlaps: \(remaining)."
                        } else {
                            statusMessage = "\(title) moved to \(afterDate.formatted(date: .abbreviated, time: .shortened))."
                        }
                    } else {
                        statusMessage = "Conflict auto-resolved."
                    }
                } else {
                    statusMessage = "Conflict action completed."
                }
                await store.refreshPersonalLayer()
                showStatusMessage = true
                return
            case .failure:
                break
            }
        }

        // Fallback path keeps existing local behavior when server action is unavailable.
        if action == "accept" {
            dismissedConflictIds.insert(conflict.id)
            statusMessage = "Conflict acknowledged."
        } else if action == "suggest" {
            statusMessage = suggestedSlotText(conflict) ?? "No alternative slot found in the current window."
        } else {
            statusMessage = resolveConflictNow(conflict) ? "Conflict auto-resolved." : "Could not auto-resolve this conflict yet."
        }
        showStatusMessage = true
    }
}

struct PersonalAggregateRow: View {
    let item: AuraRemotePersonalAggregateItem
    let fallbackIcon: String
    var onTap: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button {
            onTap()
        } label: {
        HStack(spacing: 10) {
            Image(systemName: fallbackIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AuraThemePalette.current.accentStart)
                .frame(width: 30, height: 30)
                .background(AuraThemePalette.current.accentStart.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.payload["title"] ?? item.payload["name"] ?? "Untitled")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(item.group?.name ?? "Private")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(relativeLabel(item.updatedAt))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.985 : 1)
        .opacity(isPressed ? 0.92 : 1)
        .animation(AuraMotion.quick, value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 40, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private func relativeLabel(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "now" }
        return date.formatted(.relative(presentation: .named))
    }
}

struct HomeHeroCard: View {
    let title: String
    let subtitle: String
    let detail: String
    var onRefresh: () -> Void

    var body: some View {
        let p = AuraThemePalette.current
        VStack(alignment: .leading, spacing: AuraDesignTokens.Spacing.xs) {
            HStack {
                Text("TODAY BRIEF")
                    .font(AuraDesignTokens.Typography.eyebrow)
                    .foregroundColor(.white.opacity(0.72))
                    .padding(.horizontal, AuraDesignTokens.Spacing.xs)
                    .padding(.vertical, AuraDesignTokens.Spacing.xxs + 1)
                    .background(.white.opacity(0.12), in: Capsule())
                Spacer()
                ProfileAvatarView(diameter: 34)
            }

            Text(title)
                .font(AuraDesignTokens.Typography.title)
                .foregroundColor(.white)
            Text(subtitle)
                .font(AuraDesignTokens.Typography.subtitle)
                .foregroundColor(.white.opacity(0.9))
            HStack {
                Label(detail, systemImage: "bolt.horizontal.circle.fill")
                    .font(AuraDesignTokens.Typography.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, AuraDesignTokens.Spacing.xs)
                    .padding(.vertical, AuraDesignTokens.Spacing.xs - 2)
                    .background(Color.white.opacity(0.16), in: Capsule())
                Spacer()
                Button("Refresh") {
                    onRefresh()
                }
                .font(AuraDesignTokens.Typography.bodyStrong)
                .foregroundColor(.white)
                .padding(.horizontal, AuraDesignTokens.Spacing.xs)
                .padding(.vertical, AuraDesignTokens.Spacing.xs - 2)
                .background(Color.white.opacity(0.16), in: Capsule())
            }
            .padding(.top, AuraDesignTokens.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AuraDesignTokens.Spacing.md)
        .background(
            LinearGradient(
                colors: [p.backgroundStart, p.backgroundEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.lg)
        )
        .overlay(
            Circle()
                .fill(.white.opacity(0.1))
                .frame(width: 110, height: 110)
                .blur(radius: 14)
                .offset(x: 130, y: -24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.lg)
                .stroke(.white.opacity(0.16), lineWidth: AuraDesignTokens.Stroke.subtle)
        )
        .shadow(
            color: .black.opacity(0.2),
            radius: AuraDesignTokens.Elevation.cardShadowRadius,
            y: AuraDesignTokens.Elevation.cardShadowY
        )
    }
}

struct HomeQuickActionButton: View {
    let label: String
    let icon: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        let p = AuraThemePalette.current
        Button(action: action) {
            HStack(spacing: AuraDesignTokens.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(prominent ? .white : p.accentStart)
                    .frame(width: 26, height: 26)
                    .background(
                        prominent ? Color.white.opacity(0.2) : p.accentStart.opacity(0.12),
                        in: Circle()
                    )
                Text(label)
                    .font(AuraDesignTokens.Typography.bodyStrong)
                    .lineLimit(1)
            }
            .foregroundColor(prominent ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                prominent
                    ? AnyShapeStyle(LinearGradient(
                        colors: [p.accentStart.opacity(0.9), p.accentEnd.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    : AnyShapeStyle(Color(.secondarySystemBackground).opacity(0.7)),
                in: RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.sm)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.sm)
                    .stroke(prominent ? Color.white.opacity(0.16) : p.accentStart.opacity(0.18), lineWidth: AuraDesignTokens.Stroke.subtle)
            )
        }
        .buttonStyle(AuraSoftPressButtonStyle())
    }
}

/// Edit requests: ones waiting on this member's decision (approve applies
/// the change), and the member's own recent requests with their outcome.
struct ChangeRequestsCard: View {
    @EnvironmentObject var store: EventStore

    private var recentMine: [EditProposal] {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        return store.myProposals.filter { $0.status == .pending || ($0.resolvedAt ?? .distantPast) > weekAgo }
    }

    var body: some View {
        if !store.proposalsAwaitingMe.isEmpty || !recentMine.isEmpty {
            HomeSectionCard(title: "Change Requests") {
                ForEach(store.proposalsAwaitingMe) { proposal in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(proposal.proposerName) suggests changes to \"\(proposal.targetTitle)\"")
                            .font(.system(size: 14, weight: .semibold))
                        ForEach(changeLines(proposal), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Button("Approve") {
                                AuraHaptics.success()
                                withAnimation(AuraMotion.smooth) { store.approveProposal(id: proposal.id) }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Decline", role: .destructive) {
                                AuraHaptics.warning()
                                withAnimation(AuraMotion.smooth) { store.declineProposal(id: proposal.id) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                ForEach(recentMine) { proposal in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: statusIcon(proposal.status))
                            .foregroundColor(statusColor(proposal.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your change to \"\(proposal.targetTitle)\"")
                                .font(.system(size: 13, weight: .semibold))
                            Text(statusText(proposal))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                        if proposal.status == .pending {
                            Button("Withdraw") {
                                withAnimation(AuraMotion.smooth) { store.withdrawProposal(id: proposal.id) }
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
            }
        }
    }

    /// Plain-language summary of what the request would change.
    private func changeLines(_ proposal: EditProposal) -> [String] {
        var lines: [String] = []
        func compare(_ label: String, _ old: String, _ new: String) {
            if old != new {
                lines.append(new.isEmpty ? "\(label): remove \"\(old)\"" : "\(label): \(old.isEmpty ? "" : "\"\(old)\" → ")\"\(new)\"")
            }
        }
        if let title = proposal.proposedTitle {
            compare("Name", proposal.targetTitle, title)
        }
        if let next = proposal.proposedEvent, let current = store.events.first(where: { $0.id == proposal.targetId }) {
            compare("Title", current.title, next.title)
            let fmt: (Date) -> String = { $0.formatted(date: .abbreviated, time: .shortened) }
            compare("Starts", fmt(current.startDate), fmt(next.startDate))
            compare("Ends", fmt(current.endDate), fmt(next.endDate))
            compare("Location", current.location, next.location)
            compare("Notes", current.notes, next.notes)
            if current.isAllDay != next.isAllDay { lines.append(next.isAllDay ? "Make it all-day" : "Give it a set time") }
        }
        if let next = proposal.proposedItem {
            let parentItems = (store.groupLists.first(where: { $0.id == proposal.parentId })?.items
                ?? store.groupPlans.first(where: { $0.id == proposal.parentId })?.items) ?? []
            if let current = parentItems.first(where: { $0.id == proposal.targetId }) {
                compare("Name", current.name, next.name)
                compare("Quantity", current.quantity, next.quantity)
                compare("Store", current.preferredStore ?? "", next.preferredStore ?? "")
                compare("Note", current.note, next.note)
            }
        }
        return lines.isEmpty ? ["Other details"] : lines
    }

    private func statusText(_ proposal: EditProposal) -> String {
        switch proposal.status {
        case .pending: return "Waiting for \(store.creatorName(ownerName: proposal.targetOwnerName)) to approve"
        case .approved: return "Approved"
        case .declined: return "Declined"
        case .withdrawn: return "Withdrawn"
        }
    }

    private func statusIcon(_ status: EditProposal.Status) -> String {
        switch status {
        case .pending: return "clock"
        case .approved: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .withdrawn: return "arrow.uturn.backward.circle"
        }
    }

    private func statusColor(_ status: EditProposal.Status) -> Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .declined: return .red
        case .withdrawn: return .secondary
        }
    }
}

struct HomeSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AuraDesignTokens.Spacing.xs + 2) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(AuraThemePalette.current.accentStart)
                    .frame(width: 4, height: 18)
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AuraDesignTokens.Spacing.sm + 2)
        .auraGlassCard(radius: AuraDesignTokens.Radius.md)
    }
}

struct HomeLoadingRows: View {
    var body: some View {
        VStack(spacing: AuraDesignTokens.Spacing.xs) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.sm)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 14)
            }
        }
        .redacted(reason: .placeholder)
    }
}

struct HomeInsightBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(AuraThemePalette.current.accentStart)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AuraThemePalette.current.accentStart.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HomeMemberLoadRow: View {
    let name: String
    let color: Color
    let count: Int
    let maxCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.tertiarySystemFill))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(color.opacity(0.85))
                        .frame(width: max(8, geo.size.width * CGFloat(count) / CGFloat(max(1, maxCount))))
                }
            }
            .frame(height: 8)
        }
    }
}

struct WeekPlanDraft: Identifiable {
    var id = UUID()
    var title: String
    var notes: String
    var start: Date
    var end: Date
    var categoryId: UUID
    var recurrence: Recurrence
    var assignedMemberIds: [UUID]
    var reason: String
}

struct WeekPlanningAssistantSheet: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool

    @State private var drafts: [WeekPlanDraft] = []
    @State private var selectedIds: Set<UUID> = []
    @State private var plannerMessage = ""

    var selectedCount: Int {
        drafts.filter { selectedIds.contains($0.id) }.count
    }

    var body: some View {
        NavigationView {
            List {
                Section("Assistant") {
                    Text("Aurenda generated a weekly plan from your current workload, routines, and pending family needs.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    if !plannerMessage.isEmpty {
                        Text(plannerMessage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Button {
                        regeneratePlan()
                    } label: {
                        Label("Regenerate Plan", systemImage: "arrow.clockwise")
                    }
                }

                if drafts.isEmpty {
                    Section {
                        Text("No suggestions yet. Tap Regenerate Plan to create draft events.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Weekly Drafts") {
                        ForEach(drafts) { draft in
                            Button {
                                if selectedIds.contains(draft.id) {
                                    selectedIds.remove(draft.id)
                                } else {
                                    selectedIds.insert(draft.id)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: selectedIds.contains(draft.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedIds.contains(draft.id) ? AuraThemePalette.current.accentStart : .secondary)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(draft.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text(draft.start.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.secondary)
                                        Text(draft.reason)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        if draft.recurrence != .none {
                                            Text(draft.recurrence.rawValue)
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(AuraThemePalette.current.accentStart)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(AuraThemePalette.current.accentStart.opacity(0.12), in: Capsule())
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Plan My Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply (\(selectedCount))") {
                        applySelectedDrafts()
                    }
                    .disabled(selectedCount == 0)
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                if drafts.isEmpty {
                    regeneratePlan()
                }
            }
        }
    }

    private func regeneratePlan() {
        let generated = buildDrafts()
        drafts = generated
        selectedIds = Set(generated.map(\.id))
        plannerMessage = generated.isEmpty ? "No safe suggestions found for the next 7 days." : "Generated \(generated.count) draft events. Review and apply what you want."
    }

    private func applySelectedDrafts() {
        let toApply = drafts
            .filter { selectedIds.contains($0.id) }
            .sorted { $0.start < $1.start }
        guard !toApply.isEmpty else { return }

        var applied = 0
        for draft in toApply {
            let duration = max(900, draft.end.timeIntervalSince(draft.start))
            var event = CalendarEvent(
                title: draft.title,
                notes: draft.notes,
                startDate: draft.start,
                endDate: draft.end,
                isAllDay: false,
                categoryId: draft.categoryId,
                location: "",
                alarmMins: 15,
                hasAlarm: true,
                url: "",
                attachments: [],
                recurrence: draft.recurrence,
                soundOverride: nil,
                sharedBy: nil,
                sharePermission: .edit,
                ownerName: store.activeProfileName,
                visibility: .family,
                sharedWithNames: [],
                assignedMemberIds: draft.assignedMemberIds
            )

            if let nextStart = store.nextAvailableStart(for: event, excluding: nil, searchHours: 168) {
                event.startDate = nextStart
                event.endDate = nextStart.addingTimeInterval(duration)
            }
            store.addEvent(event)
            applied += 1
        }

        AuraHaptics.success()
        plannerMessage = "Applied \(applied) planned event\(applied == 1 ? "" : "s")."
        drafts.removeAll { selectedIds.contains($0.id) }
        selectedIds.removeAll()
    }

    private func buildDrafts() -> [WeekPlanDraft] {
        let cal = Calendar.current
        let now = Date()
        var workload: [UUID: Int] = Dictionary(uniqueKeysWithValues: store.members.map { ($0.id, 0) })

        for event in store.visibleEvents {
            guard event.startDate >= now,
                  event.startDate <= (cal.date(byAdding: .day, value: 7, to: now) ?? now)
            else { continue }
            for memberId in event.assignedMemberIds {
                workload[memberId, default: 0] += 1
            }
        }

        func leastLoadedMemberId() -> UUID? {
            workload.min(by: { $0.value < $1.value })?.key
        }

        func categoryId(for hint: String) -> UUID {
            store.categories.first(where: { $0.name.caseInsensitiveCompare(hint) == .orderedSame })?.id
                ?? store.categories.first?.id
                ?? EventCategory.defaults.first!.id
        }

        func nextDate(dayOffset: Int, hour: Int) -> Date {
            let baseDay = cal.startOfDay(for: cal.date(byAdding: .day, value: dayOffset, to: now) ?? now)
            return baseDay.addingTimeInterval(TimeInterval(hour * 3600))
        }

        var plan: [WeekPlanDraft] = []
        let templates: [(RoutineAutomationTemplate, Int, String)] = [
            (.morningRoutine, 1, "A consistent morning routine reduces day-to-day friction."),
            (.weeklyGrocery, 2, "Shopping batch prevents mid-week rush."),
            (.weeklyCheckIn, 3, "A regular check-in keeps everyone aligned for the week.")
        ]

        for (template, dayOffset, reason) in templates {
            guard let memberId = leastLoadedMemberId() ?? store.members.first?.id else { continue }
            let start = nextDate(dayOffset: dayOffset, hour: template.preferredHour)
            let end = start.addingTimeInterval(Double(template.durationMinutes) * 60)
            let draft = WeekPlanDraft(
                title: template.label,
                notes: template.notes,
                start: start,
                end: end,
                categoryId: categoryId(for: template.categoryHint),
                recurrence: template.recurrence,
                assignedMemberIds: [memberId],
                reason: reason
            )
            plan.append(draft)
            workload[memberId, default: 0] += 1
        }

        if store.visibleGroupActivities.count < 3,
           let memberId = leastLoadedMemberId() ?? store.members.first?.id {
            let start = nextDate(dayOffset: 4, hour: 18)
            plan.append(.init(
                title: "Group Walk Session",
                notes: "Light movement and catch-up time.",
                start: start,
                end: start.addingTimeInterval(45 * 60),
                categoryId: categoryId(for: "Health"),
                recurrence: .none,
                assignedMemberIds: [memberId],
                reason: "Low recent activity detected."
            ))
            workload[memberId, default: 0] += 1
        }

        return plan.prefix(5).map { draft in
            var event = CalendarEvent(
                title: draft.title,
                notes: draft.notes,
                startDate: draft.start,
                endDate: draft.end,
                isAllDay: false,
                categoryId: draft.categoryId,
                location: "",
                alarmMins: 15,
                hasAlarm: true,
                url: "",
                attachments: [],
                recurrence: draft.recurrence,
                soundOverride: nil,
                sharedBy: nil,
                sharePermission: .edit,
                ownerName: store.activeProfileName,
                visibility: .family,
                sharedWithNames: [],
                assignedMemberIds: draft.assignedMemberIds
            )
            if let safeStart = store.nextAvailableStart(for: event, excluding: nil, searchHours: 168) {
                let duration = max(900, draft.end.timeIntervalSince(draft.start))
                event.startDate = safeStart
                event.endDate = safeStart.addingTimeInterval(duration)
                var updated = draft
                updated.start = event.startDate
                updated.end = event.endDate
                return updated
            }
            return draft
        }
    }
}

// A diverse set on purpose: this app's groups aren't always families, so the
// quick-schedule suggestions shouldn't assume kids/school/church for everyone --
// there's something relevant here whether the group is a family, roommates,
// a study group, a travel crew, or a church small group.
enum HomeEventQuickTemplate: CaseIterable {
    case doctorVisit
    case groceryRun
    case groupMeal
    case studySession
    case workMeeting
    case tripDeparture

    var label: String {
        switch self {
        case .doctorVisit: return "Doctor Visit"
        case .groceryRun: return "Grocery Run"
        case .groupMeal: return "Group Meal"
        case .studySession: return "Study Session"
        case .workMeeting: return "Work Meeting"
        case .tripDeparture: return "Trip Departure"
        }
    }

    var durationMinutes: Int {
        switch self {
        case .doctorVisit: return 60
        case .groceryRun: return 30
        case .groupMeal: return 90
        case .studySession: return 90
        case .workMeeting: return 60
        case .tripDeparture: return 30
        }
    }

    var categoryHint: String {
        switch self {
        case .doctorVisit: return "Appointment"
        case .groceryRun: return "Errand"
        case .groupMeal: return "Social"
        case .studySession: return "Class · Study"
        case .workMeeting: return "Meeting"
        case .tripDeparture: return "Travel"
        }
    }

    var recurrence: Recurrence {
        .none
    }
}

// Same reasoning as the quick templates above: a mix that's useful whether
// the group is a family, a roommate household, or a small group that meets
// weekly for any reason (study, church, hobby) -- no single one is assumed.
enum RoutineAutomationTemplate: CaseIterable {
    case morningRoutine
    case medicationCheck
    case weeklyGrocery
    case choreRotation
    case weeklyCheckIn

    var label: String {
        switch self {
        case .morningRoutine: return "Morning Routine"
        case .medicationCheck: return "Medication Check"
        case .weeklyGrocery: return "Weekly Grocery Run"
        case .choreRotation: return "Chore Rotation"
        case .weeklyCheckIn: return "Weekly Check-In"
        }
    }

    var durationMinutes: Int {
        switch self {
        case .morningRoutine: return 45
        case .medicationCheck: return 15
        case .weeklyGrocery: return 90
        case .choreRotation: return 30
        case .weeklyCheckIn: return 40
        }
    }

    var categoryHint: String {
        switch self {
        case .morningRoutine: return "Personal"
        case .medicationCheck: return "Health"
        case .weeklyGrocery: return "Errand"
        case .choreRotation: return "Home · Chores"
        case .weeklyCheckIn: return "Social"
        }
    }

    var recurrence: Recurrence {
        switch self {
        case .medicationCheck: return .daily
        case .weeklyGrocery, .choreRotation, .weeklyCheckIn, .morningRoutine: return .weekly
        }
    }

    var notes: String {
        switch self {
        case .morningRoutine: return "Prep for the day: bags, essentials, quick checklist."
        case .medicationCheck: return "Confirm medication taken and log any notes."
        case .weeklyGrocery: return "Top-up core pantry items and produce for the week."
        case .choreRotation: return "Rotate shared chores and check off completed tasks."
        case .weeklyCheckIn: return "Catch up, share updates, and plan the week ahead."
        }
    }

    var preferredHour: Int {
        switch self {
        case .morningRoutine: return 7
        case .medicationCheck: return 20
        case .weeklyGrocery: return 17
        case .choreRotation: return 18
        case .weeklyCheckIn: return 19
        }
    }

    func preset(in store: EventStore) -> EventDraftPreset {
        var base = EventDraftPreset.defaultForActiveMember(in: store)
        let start = EventDraftPreset.scheduledDate(hour: preferredHour, minute: 0)
        base.title = label
        base.notes = notes
        base.start = start
        base.end = start.addingTimeInterval(Double(durationMinutes) * 60)
        base.recurrence = recurrence
        base.categoryId = store.categories.first(where: { $0.name.caseInsensitiveCompare(categoryHint) == .orderedSame })?.id ?? base.categoryId
        return base
    }
}

struct EventDraftPreset {
    var title: String
    var notes: String
    var location: String
    var start: Date
    var end: Date
    var categoryId: UUID?
    var visibility: VisibilityScope
    var sharedWithNames: [String]
    var assignedMemberIds: [UUID]
    var hasAlarm: Bool
    var alarmMins: Int
    var recurrence: Recurrence

    static func defaultForActiveMember(in store: EventStore) -> EventDraftPreset {
        let roundedStart = roundedToHalfHour(from: Date().addingTimeInterval(1800))
        let memberIds = store.activeMember.map { [$0.id] } ?? []
        return .init(
            title: "",
            notes: "",
            location: "",
            start: roundedStart,
            end: roundedStart.addingTimeInterval(3600),
            categoryId: store.categories.first?.id,
            visibility: .family,
            sharedWithNames: [],
            assignedMemberIds: memberIds,
            hasAlarm: true,
            alarmMins: 15,
            recurrence: .none
        )
    }

    static func from(template: HomeEventQuickTemplate, store: EventStore) -> EventDraftPreset {
        var base = defaultForActiveMember(in: store)
        let start = roundedToHalfHour(from: Date().addingTimeInterval(1800))
        base.title = template.label
        base.start = start
        base.end = start.addingTimeInterval(Double(template.durationMinutes) * 60)
        base.categoryId = store.categories.first(where: { $0.name.caseInsensitiveCompare(template.categoryHint) == .orderedSame })?.id ?? base.categoryId
        base.recurrence = template.recurrence
        return base
    }

    static func roundedToHalfHour(from date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = comps.minute ?? 0
        comps.minute = minute < 30 ? 30 : 0
        if minute >= 30 {
            comps.hour = (comps.hour ?? 0) + 1
        }
        comps.second = 0
        return cal.date(from: comps) ?? date
    }

    static func scheduledDate(hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        let todayTarget = cal.date(from: comps) ?? Date()
        if todayTarget > Date() {
            return roundedToHalfHour(from: todayTarget)
        }
        return roundedToHalfHour(from: cal.date(byAdding: .day, value: 1, to: todayTarget) ?? todayTarget)
    }
}
