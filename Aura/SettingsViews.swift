import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

// MARK: - Group Members

struct GroupMembersView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("householdCode") private var householdCode = ""
    @State private var isWorking = false
    @State private var message = ""
    @State private var pendingRemoval: AuraRemoteGroupMemberRecord?
    @State private var pendingTransfer: AuraRemoteGroupMemberRecord?

    var body: some View {
        NavigationView {
            ZStack {
                AuraAtmosphericBackground()
                List {
                    joinCodeSection
                    membersSection
                    if store.isActiveGroupOwner {
                        activitySection
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(store.activeServerGroupName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await store.refreshActiveGroupAdminData() }
            .refreshable { await store.refreshActiveGroupAdminData() }
            .alert("Remove member?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    guard let record = pendingRemoval else { return }
                    Task {
                        isWorking = true
                        _ = await store.removeActiveGroupMember(userId: record.membership.userId)
                        isWorking = false
                    }
                }
            } message: {
                Text("\(pendingRemoval?.user?.displayName ?? "This member") will lose access to this group.")
            }
            .alert("Transfer ownership?", isPresented: Binding(get: { pendingTransfer != nil }, set: { if !$0 { pendingTransfer = nil } })) {
                Button("Cancel", role: .cancel) {}
                Button("Transfer", role: .destructive) {
                    guard let record = pendingTransfer else { return }
                    Task {
                        isWorking = true
                        _ = await store.transferActiveGroupOwnership(to: record.membership.userId)
                        isWorking = false
                    }
                }
            } message: {
                Text("\(pendingTransfer?.user?.displayName ?? "This member") becomes the new owner. You'll be moved to Admin.")
            }
        }
    }

    private var joinCodeSection: some View {
        Section {
            HStack {
                Text(householdCode.isEmpty ? "——————" : householdCode)
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(AuraThemePalette.current.accentStart)
                    .tracking(2)
                Spacer()
                if store.isActiveGroupOwner {
                    Button {
                        Task {
                            isWorking = true
                            _ = await store.regenerateActiveGroupCode()
                            isWorking = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isWorking)
                }
                Button {
                    UIPasteboard.general.string = householdCode
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                ShareLink(item: "Join my Aurenda group \"\(store.activeServerGroupName)\" — use code \(householdCode) in the app.") {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .auraGlassCard(radius: AuraDesignTokens.Radius.md)
            .listRowSeparator(.hidden)
        } header: {
            Text("JOIN CODE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    private var membersSection: some View {
        Section {
            if store.isLoadingActiveGroupAdmin && store.activeGroupMemberRecords.isEmpty {
                ProgressView()
                    .listRowBackground(Color.clear)
            } else if store.activeGroupMemberRecords.isEmpty {
                Text("No members yet.")
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(store.activeGroupMemberRecords) { record in
                    memberRow(record)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        } header: {
            Text("MEMBERS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    private func memberRow(_ record: AuraRemoteGroupMemberRecord) -> some View {
        let isSelf = record.membership.userId == store.serverUserId
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.user?.displayName.isEmpty == false ? record.user!.displayName : "Member")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                if let email = record.user?.email {
                    Text(email)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            roleMenu(for: record, isSelf: isSelf)
        }
        .padding(AuraDesignTokens.Spacing.sm)
        .auraGlassCard(radius: AuraDesignTokens.Radius.md)
        .swipeActions(edge: .trailing) {
            if store.isActiveGroupOwner && !isSelf {
                Button(role: .destructive) { pendingRemoval = record } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func roleMenu(for record: AuraRemoteGroupMemberRecord, isSelf: Bool) -> some View {
        if store.isActiveGroupOwner && !isSelf {
            Menu {
                ForEach(["Owner", "Admin", "Member", "Junior"], id: \.self) { role in
                    Button(role) {
                        Task {
                            if role == "Owner" {
                                pendingTransfer = record
                            } else {
                                isWorking = true
                                _ = await store.updateActiveGroupMemberRole(userId: record.membership.userId, role: role)
                                isWorking = false
                            }
                        }
                    }
                }
            } label: {
                roleBadge(record.membership.role)
            }
        } else {
            roleBadge(record.membership.role)
        }
    }

    private func roleBadge(_ role: String) -> some View {
        Text(role)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                LinearGradient(colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd], startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
    }

    private var activitySection: some View {
        Section {
            if store.activeGroupAuditEntries.isEmpty {
                Text("No activity yet.")
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(store.activeGroupAuditEntries.prefix(20)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.action.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 13, weight: .semibold))
                        if let details = entry.details, !details.isEmpty {
                            Text(details)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Color.clear)
                }
            }
        } header: {
            Text("ACTIVITY LOG")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Profile Picture Storage

enum ProfileImageStore {
    private static var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("aura.profileImage.jpg")
    }

    static func load() -> UIImage? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage) {
        guard let url = fileURL, let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: .atomic)
        NotificationCenter.default.post(name: .auraProfileImageChanged, object: nil)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
        NotificationCenter.default.post(name: .auraProfileImageChanged, object: nil)
    }
}

extension Notification.Name {
    static let auraProfileImageChanged = Notification.Name("AuraProfileImageChanged")
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ProfileAvatarView: View {
    var diameter: CGFloat = 56
    @State private var image: UIImage? = ProfileImageStore.load()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "person.fill")
                        .font(.system(size: diameter * 0.42, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
        .onReceive(NotificationCenter.default.publisher(for: .auraProfileImageChanged)) { _ in
            image = ProfileImageStore.load()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: EventStore
    @AppStorage("colorScheme") private var scheme = "system"
    @AppStorage("widgetThemeJSON") private var widgetThemeJSON = ""
    @AppStorage("profileDisplayName") private var profileDisplayName = ""
    @AppStorage("aura.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("aura.allowOfflineMode") private var allowOfflineMode = false
    @AppStorage("authHeroMode") private var authHeroMode = "collage"
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @AppStorage("backendAccountEmail") private var backendAccountEmail = ""
    @AppStorage("backendHouseholdName") private var backendStoredGroupName = ""
    @AppStorage("enableInAppBanner") private var enableInAppBanner = true
    @AppStorage("enableActionableReminders") private var enableActionableReminders = true
    @AppStorage("enableReminderSnooze") private var enableReminderSnooze = true
    @AppStorage("enableSmartReminderMessaging") private var enableSmartReminderMessaging = true
    @AppStorage("reminderSnoozeMinutes") private var reminderSnoozeMinutes = 10
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
    @State private var profilePickerItem: PhotosPickerItem?
    @State private var hasProfileImage = ProfileImageStore.load() != nil
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var serverMessage = ""
    @State private var isServerWorking = false
    @State private var showDeleteAccount = false
    @State private var isExporting = false
    @State private var exportedFile: IdentifiableURL?
    @State private var exportError = ""

    var allThemes: [WidgetGradientTheme] { WidgetGradientTheme.presets + customThemes }
    var selectedTheme: WidgetGradientTheme? { allThemes.first { $0.id == selectedThemeId } }
    var dailyStepVisibility: VisibilityScope { VisibilityScope(rawValue: dailyStepVisibilityRaw) ?? .personal }
    var dailyStepSharedWithNames: [String] {
        dailyStepSharedWithNamesRaw.split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
    }
    var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build)) · iOS 16+"
    }

    var sharedBySender: [(String, Int)] {
        let grouped = Dictionary(grouping: store.events.filter { $0.sharedBy != nil }) { $0.sharedBy ?? "Unknown" }
        return grouped
            .map { ($0.key, $0.value.count) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    var readinessChecks: [(title: String, isReady: Bool, detail: String)] {
        [
            (
                "Profile",
                !profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Set display name for sharing"
            ),
            (
                "Workspace Members",
                !store.members.isEmpty,
                "Add at least one member profile"
            ),
            (
                "Connection",
                store.hasServerGroup,
                "Sign in and create or join a group"
            ),
            (
                "Notifications",
                enableInAppBanner || enableActionableReminders,
                "Enable at least one reminder channel"
            )
        ]
    }

    var releaseReadyCount: Int {
        readinessChecks.filter { $0.isReady }.count
    }

    var body: some View {
        NavigationView {
            ZStack {
                AuraAtmosphericBackground()
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
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Setup Progress")
                                .font(.system(size: 16, weight: .bold))
                            Text("A quick snapshot of the release-ready setup state.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(releaseReadyCount)/\(readinessChecks.count)")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(AuraThemePalette.current.accentStart)
                            Text("ready")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }

                    ProgressView(value: Double(releaseReadyCount), total: Double(readinessChecks.count))
                        .tint(AuraThemePalette.current.accentStart)

                    ForEach(readinessChecks, id: \ .title) { check in
                        HStack {
                            Image(systemName: check.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(check.isReady ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(check.isReady ? "Ready" : check.detail)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                } header: {
                    Text("Setup Snapshot")
                }

                Section {
                    Toggle("Allow Offline Mode", isOn: $allowOfflineMode)

                    Picker("Auth Hero Style", selection: $authHeroMode) {
                        Text("Collage").tag("collage")
                        Text("Single").tag("single")
                    }
                    .pickerStyle(.segmented)

                    Button {
                        hasSeenOnboarding = false
                    } label: {
                        Label("Replay Onboarding", systemImage: "sparkles.rectangle.stack")
                    }

                    Button {
                        allowOfflineMode = false
                        store.clearServerSession()
                        serverMessage = "Auth flow reset. The sign-in screen will appear on next launch."
                    } label: {
                        Label("Reset Auth Flow", systemImage: "arrow.counterclockwise.circle")
                    }
                } header: {
                    Text("Sync & Backup")
                } footer: {
                    Text("Use this panel for offline mode, onboarding replay, and sync-related recovery.")
                }

                Section {
                    if store.members.isEmpty {
                        Text("No local profiles yet.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Assign as", selection: Binding(
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

                    Button {
                        showAddMember = true
                    } label: {
                        Label("Add Local Profile", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Local Profiles")
                } footer: {
                    Text("Local profiles don't have accounts or logins -- use them to assign events and activities to people (like young kids) who aren't signed into Aurenda themselves. This is separate from your actual Group Members.")
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
                            Label(scope.displayName, systemImage: scope.icon).tag(scope)
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
                    Text("The active member can choose whether their steps are visible to others.")
                }

                if store.hasServerSession {
                    Section {
                        HStack(spacing: 14) {
                            ProfileAvatarView(diameter: 60)
                            VStack(alignment: .leading, spacing: 6) {
                                PhotosPicker(selection: $profilePickerItem, matching: .images) {
                                    Text(hasProfileImage ? "Change Photo" : "Add Photo")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                if hasProfileImage {
                                    Button(role: .destructive) {
                                        ProfileImageStore.clear()
                                        hasProfileImage = false
                                    } label: {
                                        Text("Remove Photo")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                }
                            }
                            Spacer()
                        }
                        .onChange(of: profilePickerItem) { newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    ProfileImageStore.save(uiImage)
                                    await MainActor.run { hasProfileImage = true }
                                }
                            }
                        }

                        LabeledContent("Signed in as", value: store.serverAccountEmail.isEmpty ? backendAccountEmail : store.serverAccountEmail)
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
                    } header: {
                        Text("Profile")
                    }

                    Section {
                        AuraSecureField(placeholder: "Current password", text: $currentPassword)
                        AuraSecureField(placeholder: "New password (min 8)", text: $newPassword)
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
                    } header: {
                        Text("Security")
                    }

                    Section {
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
                            Label("Refresh Account Info", systemImage: "arrow.clockwise.circle")
                        }

                        Button {
                            isExporting = true
                            exportError = ""
                            Task {
                                let result = await store.exportAccountData()
                                await MainActor.run {
                                    isExporting = false
                                    switch result {
                                    case .success(let url):
                                        exportedFile = IdentifiableURL(url: url)
                                    case .failure(let error):
                                        exportError = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            if isExporting {
                                ProgressView()
                            } else {
                                Label("Export My Data", systemImage: "square.and.arrow.up")
                            }
                        }
                        .disabled(isExporting)

                        Button(role: .destructive) {
                            store.clearServerSession()
                            serverPassword = ""
                            serverMessage = "Signed out."
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } footer: {
                        Text("\"Refresh Account Info\" re-fetches your profile and role from the server -- use it if something looks out of date.")
                    }

                    Section {
                        Button(role: .destructive) {
                            showDeleteAccount = true
                        } label: {
                            Label("Delete Account", systemImage: "trash.fill")
                        }
                    } footer: {
                        Text("Permanently deletes your account. Groups only you belong to are deleted with it; groups you share are handed to another member instead.")
                    }

                    if isServerWorking {
                        Section { ProgressView() }
                    }
                    if !serverMessage.isEmpty {
                        Section {
                            Text(serverMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    if !exportError.isEmpty {
                        Section {
                            Text(exportError)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                } else {
                Section {
                        TextField("Email", text: $serverEmail)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.emailAddress)
                        AuraSecureField(placeholder: "Password", text: $serverPassword)
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

                        if isServerWorking {
                            ProgressView()
                        }
                        if !serverMessage.isEmpty {
                            Text(serverMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Account Access")
                    } footer: {
                        Text("Sign in to sync securely across devices and workspaces.")
                    }
                }

                if store.hasServerSession {
                    Section("Server Role") {
                        LabeledContent("Role", value: store.serverMembershipRole.isEmpty ? "Not linked" : store.serverMembershipRole)
                        LabeledContent("Platform admin", value: store.serverIsAdmin ? "Yes" : "No")
                    }
                }

                if store.hasServerSession && store.isServerOwner {
                    Section {
                        if store.activeServerGroupId.isEmpty {
                            Text("Select an active group to view conflict history.")
                                .foregroundColor(.secondary)
                        } else if store.serverGroupConflictHistoryEntries.isEmpty {
                            Text("No conflict history yet for this group.")
                                .foregroundColor(.secondary)
                        }

                        ForEach(store.serverGroupConflictHistoryEntries.prefix(12)) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(conflictActionLabel(entry.action))
                                        .font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    Text(relativeServerTime(entry.createdAt))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                if !entry.details.isEmpty {
                                    Text(entry.details)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Conflict Resolution History")
                    } footer: {
                        Text("Tracks conflict acknowledgements, suggested slots, and auto-fix actions for the active group.")
                    }
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
                    Toggle("Actionable Event Reminders", isOn: $enableActionableReminders)
                    Toggle("Allow Snooze Action", isOn: $enableReminderSnooze)
                        .disabled(!enableActionableReminders)
                    Toggle("Smart Reminder Messaging", isOn: $enableSmartReminderMessaging)

                    Stepper(value: $reminderSnoozeMinutes, in: 5...60, step: 5) {
                        Text("Default Snooze: \(reminderSnoozeMinutes) min")
                    }
                    .disabled(!enableActionableReminders || !enableReminderSnooze)

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

                Section {
                    Button {
                        let report = store.runDataIntegritySweep()
                        serverMessage = report.totalFixes == 0
                            ? "Integrity sweep complete. No issues found."
                            : "Integrity sweep fixed \(report.totalFixes) issue\(report.totalFixes == 1 ? "" : "s")."
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Run Integrity Sweep", systemImage: "checkmark.shield")
                            Text("Checks this device's own data for broken references -- e.g. events pointing at a deleted category -- and fixes them.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        store.rebuildScheduledNotifications()
                        serverMessage = "Notifications rebuilt from current events."
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Rebuild Event Notifications", systemImage: "bell.and.waveform")
                            Text("Re-schedules all reminder notifications from your current events. Use this if reminders stop firing.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Maintenance")
                } footer: {
                    Text("These only affect your own device's data, not other members of your group.")
                }

                // ── Groups ─────────────────────────────
                if store.hasServerSession {
                    Section {
                        Label("Manage groups, join codes, and members from the Group Members screen -- tap the people icon at the top of the app.", systemImage: "person.2.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    } header: {
                        Text("Groups")
                    }
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
                Section {
                    VStack(spacing: 10) {
                        Image("AppIconGraphic")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        Text("Aurenda")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        Text("Version \(appVersionString)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("About")
                }
                }
                .scrollContentBackground(.hidden)
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
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountView(isPresented: $showDeleteAccount).environmentObject(store)
            }
            .sheet(item: $exportedFile) { file in
                ActivityShareSheet(activityItems: [file.url])
            }
            .onChange(of: enableActionableReminders) { _ in
                NotificationManager.shared.configureReminderCategories()
            }
            .onChange(of: enableReminderSnooze) { _ in
                NotificationManager.shared.configureReminderCategories()
            }
            .onAppear {
                stepCustomNames = Set(dailyStepSharedWithNames)
                serverEmail = backendAccountEmail
                serverDisplayName = profileDisplayName
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

    private func conflictActionLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func relativeServerTime(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else {
            return iso
        }
        return date.formatted(.relative(presentation: .named))
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
    @State private var searchText = ""
    @State private var showConflictsOnly = false
    @State private var infoMessage = ""

    var grouped: [(sender: String, events: [CalendarEvent])] {
        let items = store.events.filter { $0.sharedBy != nil }
        let g = Dictionary(grouping: items) { $0.sharedBy ?? "Unknown" }
        return g
            .map { (sender: $0.key, events: $0.value.sorted { $0.startDate < $1.startDate }) }
            .sorted { $0.sender.localizedCaseInsensitiveCompare($1.sender) == .orderedAscending }
    }

    var conflictIds: Set<UUID> {
        Set(store.events
            .filter { $0.sharedBy != nil }
            .filter { !store.conflictsForSharedEvent($0).isEmpty }
            .map(\.id)
        )
    }

    var filteredGrouped: [(sender: String, events: [CalendarEvent])] {
        grouped.compactMap { group in
            let filteredEvents = group.events.filter { event in
                let matchesText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    event.title.localizedCaseInsensitiveContains(searchText) ||
                    (event.sharedBy ?? "").localizedCaseInsensitiveContains(searchText)
                let passesConflict = !showConflictsOnly || conflictIds.contains(event.id)
                return matchesText && passesConflict
            }
            return filteredEvents.isEmpty ? nil : (group.sender, filteredEvents)
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Show conflicts only", isOn: $showConflictsOnly)
                    if !infoMessage.isEmpty {
                        Text(infoMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if store.isBootstrapping {
                    SharedSkeletonListView()
                        .transition(.opacity)
                } else if filteredGrouped.isEmpty {
                    Text("No shared events")
                        .foregroundColor(.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                ForEach(filteredGrouped, id: \.sender) { group in
                    Section {
                        ForEach(group.events) { e in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(e.title)
                                        .font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    if conflictIds.contains(e.id) {
                                        Label("Conflict", systemImage: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.12), in: Capsule())
                                    }
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
                                        if conflictIds.contains(e.id) && e.sharePermission == .edit {
                                            Button("Resolve Conflict") {
                                                if store.resolveSharedEventConflict(id: e.id) {
                                                    AuraHaptics.success()
                                                    infoMessage = "Moved \(e.title) to the next free slot."
                                                } else {
                                                    AuraHaptics.warning()
                                                    infoMessage = "Could not auto-resolve conflict for \(e.title)."
                                                }
                                            }
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
            .animation(AuraMotion.smooth, value: filteredGrouped.isEmpty)
            .searchable(text: $searchText, prompt: "Search sender or event")
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
    @State private var searchText = ""
    @State private var selectedAction: SharedActivityAction? = nil

    var filteredEntries: [SharedActivityEntry] {
        store.sharedActivity.filter { entry in
            let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesText = text.isEmpty ||
                entry.eventTitle.localizedCaseInsensitiveContains(text) ||
                entry.sender.localizedCaseInsensitiveContains(text) ||
                entry.details.localizedCaseInsensitiveContains(text)
            let matchesAction = selectedAction == nil || entry.action == selectedAction
            return matchesText && matchesAction
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section("Filters") {
                    Picker("Action", selection: $selectedAction) {
                        Text("All").tag(Optional<SharedActivityAction>.none)
                        ForEach(SharedActivityAction.allCases, id: \.self) { action in
                            Text(action.rawValue).tag(Optional(action))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if store.isBootstrapping {
                    SharedSkeletonListView()
                        .transition(.opacity)
                } else if filteredEntries.isEmpty {
                    Text("No shared activity yet")
                        .foregroundColor(.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    ForEach(filteredEntries) { entry in
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
            .animation(AuraMotion.smooth, value: filteredEntries.isEmpty)
            .searchable(text: $searchText, prompt: "Search activity")
            .navigationTitle("Shared Activity Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !store.sharedActivity.isEmpty {
                        Button("Clear") {
                            store.clearSharedActivity()
                        }
                    }
                }
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
