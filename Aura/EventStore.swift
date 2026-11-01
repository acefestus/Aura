import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

// MARK: - Event Store

class EventStore: ObservableObject {
    @Published var events:     [CalendarEvent] = []
    @Published var categories: [EventCategory] = []
    @Published var sharedActivity: [SharedActivityEntry] = []
    @Published var members: [GroupMember] = []
    @Published var groupLists: [GroupList] = []
    @Published var groupPlans: [GroupPlan] = []
    @Published var groupStores: [GroupStore] = []
    @Published var proposals: [EditProposal] = []
    /// Who's currently in the active group, from the latest sync reply.
    @Published private(set) var activeGroupMembers: [AuraRemoteMemberRef] = []
    private(set) var deletedIds: [String: Date] = [:]
    private var hasPendingPush = false
    @Published var groupActivities: [GroupActivity] = []
    @Published var groupStepSnapshots: [GroupStepSnapshot] = []
    @Published var activeActivitySession: LiveGroupActivitySession? = nil
    @Published var isBootstrapping = true
    @Published var syncStatus = "Sync disabled"
    @Published var serverAccountEmail = ""
    @Published var serverGroupName = ""
    @Published var serverMembershipRole = ""
    @Published var serverIsAdmin = false
    @Published var serverUserId = ""
    @Published var serverGroups: [AuraRemoteGroupRecord] = []
    @Published var activeGroupMemberRecords: [AuraRemoteGroupMemberRecord] = []
    @Published var activeGroupAuditEntries: [AuraRemoteAuditEntry] = []
    @Published var isLoadingActiveGroupAdmin = false
    @Published var serverGroupConflictHistoryEntries: [AuraRemoteGroupConflictHistoryEntry] = []
    @Published var personalMasterCalendarItems: [AuraRemotePersonalAggregateItem] = []
    @Published var personalTaskItems: [AuraRemotePersonalAggregateItem] = []
    @Published var personalPlanItems: [AuraRemotePersonalAggregateItem] = []
    @Published var personalRoutineItems: [AuraRemotePersonalAggregateItem] = []
    @Published var personalConflictItems: [AuraRemoteConflictRecord] = []
    @Published var isLoadingPersonalLayer = false
    @AppStorage("colorScheme") var scheme: String = "system"
    @AppStorage("profileDisplayName") private var profileDisplayName = ""
    @AppStorage("activeFamilyMemberId") private var activeMemberId = ""
    @AppStorage("householdCode") private var householdCode = ""
    @AppStorage("backendUserId") private var storedUserId = ""
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @AppStorage("backendAuthToken") private var backendAuthToken = ""
    @AppStorage("backendAccountEmail") private var backendAccountEmail = ""
    @AppStorage("backendHouseholdId") private var backendGroupId = ""
    @AppStorage("backendHouseholdName") private var backendStoredGroupName = ""
    @AppStorage("activeGroupId") private var activeGroupId = ""
    @AppStorage("shareDailySteps") private var shareDailySteps = false
    @AppStorage("dailyStepVisibility") private var dailyStepVisibilityRaw = VisibilityScope.personal.rawValue
    @AppStorage("dailyStepSharedWithNames") private var dailyStepSharedWithNamesRaw = ""

    private let eKey = "aura.events"
    private let cKey = "aura.categories"
    private let aKey = "aura.sharedActivity"
    private let mKey = "aura.familyMembers"
    private let lKey = "aura.familyLists"
    private let pKey = "aura.familyPlans"
    private let fKey = "aura.familyActivities"
    private let sKey = "aura.familyStepSnapshots"
    private let liveActivityKey = "aura.liveFamilyActivity"
    private let storesKey = "aura.groupStores"
    private let proposalsKey = "aura.proposals"
    private let deletedKey = "aura.deletedIds"
    private var shared: UserDefaults { UserDefaults(suiteName: "group.com.personal.aura") ?? .standard }
    private var syncDebounceTask: Task<Void, Never>? = nil
    private var periodicPullTask: Task<Void, Never>? = nil
    private var applyingRemoteSnapshot = false

    var activeProfileName: String {
        if let activeMember {
            return activeMember.name
        }
        let clean = profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Aurenda User" : clean
    }

    var activeMember: GroupMember? {
        guard let id = UUID(uuidString: activeMemberId) else { return nil }
        return members.first(where: { $0.id == id })
    }

    var currentViewerName: String { activeProfileName }

    var dailyStepVisibility: VisibilityScope {
        VisibilityScope(rawValue: dailyStepVisibilityRaw) ?? .personal
    }

    var dailyStepSharedWithNames: [String] {
        dailyStepSharedWithNamesRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var currentGroupCode: String {
        householdCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentBackendBaseURL: String {
        backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasServerSession: Bool {
        !currentBackendBaseURL.isEmpty && !backendAuthToken.isEmpty
    }

    var hasServerGroup: Bool {
        hasServerSession && !backendGroupId.isEmpty
    }

    var activeServerGroupId: String {
        activeGroupId
    }

    var activeServerGroup: AuraRemoteGroupRecord? {
        serverGroups.first(where: { $0.group.id == activeGroupId })
    }

    var activeServerGroupName: String {
        activeServerGroup?.group.name ?? "No Group"
    }

    var hasServerGroups: Bool {
        !serverGroups.isEmpty
    }

    var isServerOwner: Bool {
        serverMembershipRole.caseInsensitiveCompare("Owner") == .orderedSame
    }

    var isActiveGroupOwner: Bool {
        (activeServerGroup?.membership.role ?? "").caseInsensitiveCompare("Owner") == .orderedSame
    }

    func setActiveServerGroup(id: String) {
        guard let selected = serverGroups.first(where: { $0.group.id == id }) else { return }
        changeActiveGroup(to: selected.group.id)
        backendGroupId = selected.group.id
        backendStoredGroupName = selected.group.name
        serverGroupName = selected.group.name
        householdCode = selected.group.code
        serverMembershipRole = selected.membership.role
        syncStatus = "Active group: \(selected.group.name)"
        syncActiveGroupNameToWidget(selected.group.name)
        if hasServerSession && isServerOwner {
            Task { @MainActor [weak self] in
                await self?.refreshServerAdminData()
            }
        }
    }

    /// Widgets can't hold a live server session or make network calls on their
    /// own timeline schedule, so the only way they can be V2-group-aware at
    /// all is if the main app writes the active group's name into shared App
    /// Group storage whenever it changes.
    private func syncActiveGroupNameToWidget(_ name: String) {
        shared.set(name, forKey: "aura.activeGroupName")
        WidgetCenter.shared.reloadAllTimelines()
    }

    init() {
        // The Railway service was renamed after some installs already persisted
        // the old domain in @AppStorage; a first-launch-only default wouldn't
        // reach those. Repair it unconditionally so an existing install with a
        // valid session doesn't keep silently failing every server call.
        if backendBaseURL == "https://aura-family-backend-production.up.railway.app" {
            backendBaseURL = "https://aurenda.up.railway.app"
        }
        loadCats()
        loadEvents()
        loadSharedActivity()
        loadMembers()
        loadGroupLists()
        loadGroupPlans()
        loadGroupActivities()
        loadGroupStepSnapshots()
        loadGroupStores()
        loadProposals()
        loadDeletedIds()
        loadLiveActivitySession()
        serverUserId = storedUserId
        serverAccountEmail = backendAccountEmail
        serverGroupName = backendStoredGroupName
        if hasServerSession {
            Task { @MainActor [weak self] in
                await self?.refreshServerContext()
            }
        }
        _ = runDataIntegritySweep()
        NotificationCenter.default.addObserver(forName: .auraRemoteChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.pullSnapshot() }
        }
        NotificationCenter.default.addObserver(forName: .auraPushTokenUpdated, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.registerPushTokenIfPossible() }
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
        recordDeletion([id])
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
        var e = e
        e.createdByUserId = currentUserId.isEmpty ? nil : currentUserId
        e.modifiedAt = Date()
        events.append(e)
        events.sort { $0.startDate < $1.startDate }
        saveEvents()
        scheduleReminderIfNeeded(e)
    }

    enum EditOutcome { case applied, proposed, notAllowed }

    /// The creator's edits apply directly; anyone else's become a request the
    /// creator approves or declines.
    @discardableResult
    func updateEvent(_ e: CalendarEvent) -> EditOutcome {
        guard let i = events.firstIndex(where: { $0.id == e.id }) else { return .notAllowed }
        guard events[i].sharePermission == .edit else { return .notAllowed }
        guard canEdit(events[i]) else {
            proposeEventChange(original: events[i], proposed: e)
            return .proposed
        }
        var e = e
        e.createdByUserId = events[i].createdByUserId
        e.modifiedAt = Date()
        NotificationManager.shared.cancel(e.id)
        events[i] = e
        events.sort { $0.startDate < $1.startDate }
        saveEvents()
        scheduleReminderIfNeeded(e)
        return .applied
    }

    /// Schedules a reminder and, unlike a bare fire-and-forget call, actually
    /// tells the user when it silently wouldn't fire (alert time already
    /// past, or notifications denied in iOS Settings) -- previously this was
    /// only a console print no one ever saw.
    func scheduleReminderIfNeeded(_ e: CalendarEvent) {
        guard e.hasAlarm else { return }
        Task { @MainActor in
            let result = await NotificationManager.shared.schedule(e, cat: category(for: e.categoryId))
            let message: String?
            switch result {
            case .scheduled:
                message = nil
            case .skippedPastFireTime:
                message = "\"\(e.title)\" won't get an alert -- its reminder time has already passed."
            case .notAuthorized:
                message = "\"\(e.title)\" won't get an alert -- notifications are off for Aurenda in iOS Settings."
            case .failed:
                message = "Couldn't schedule a reminder for \"\(e.title)\"."
            }
            guard let message else { return }
            NotificationCenter.default.post(
                name: .auraInAppBanner,
                object: nil,
                userInfo: ["title": "Reminder Not Set", "message": message]
            )
        }
    }

    func deleteEvent(id: UUID) {
        guard let e = events.first(where: { $0.id == id }), e.sharePermission != .view, canDelete(e) else { return }
        NotificationManager.shared.cancel(id)
        events.removeAll { $0.id == id }
        recordDeletion([id])
        saveEvents()
    }

    func rebuildScheduledNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        let toSchedule = events.filter { $0.hasAlarm }
        Task { @MainActor in
            for event in toSchedule {
                _ = await NotificationManager.shared.schedule(event, cat: category(for: event.categoryId))
            }
        }
        syncStatus = "Notifications rebuilt"
    }

    @discardableResult
    func runDataIntegritySweep() -> DataIntegrityReport {
        var report = DataIntegrityReport()
        let validCategoryIds = Set(categories.map(\.id))
        let validMemberIds = Set(members.map(\.id))
        let fallbackCategoryId = categories.first?.id

        for idx in events.indices {
            if events[idx].endDate <= events[idx].startDate {
                events[idx].endDate = events[idx].startDate.addingTimeInterval(60 * 30)
                report.fixedEventTimeRanges += 1
            }
            if !validCategoryIds.contains(events[idx].categoryId), let fallbackCategoryId {
                events[idx].categoryId = fallbackCategoryId
                report.repairedCategoryReferences += 1
            }
            let originalCount = events[idx].assignedMemberIds.count
            events[idx].assignedMemberIds = events[idx].assignedMemberIds.filter { validMemberIds.contains($0) }
            if events[idx].assignedMemberIds.count != originalCount {
                report.removedInvalidAssignments += (originalCount - events[idx].assignedMemberIds.count)
            }
        }

        if report.totalFixes > 0 {
            events.sort { $0.startDate < $1.startDate }
            saveEvents()
            syncStatus = "Data normalized (\(report.totalFixes) fixes)"
        }
        return report
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

    func eventFromPayload(_ payload: [String: String]) -> CalendarEvent? {
        if let rawId = payload["id"],
           let id = UUID(uuidString: rawId),
           let exact = events.first(where: { $0.id == id }) {
            return exact
        }

        let title = payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty {
            return nil
        }

        if let rawStart = payload["startDate"],
           let start = ISO8601DateFormatter().date(from: rawStart),
           let exactByTime = events.first(where: {
               $0.title.caseInsensitiveCompare(title) == .orderedSame &&
               abs($0.startDate.timeIntervalSince(start)) < 60
           }) {
            return exactByTime
        }

        return events.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame })
    }

    /// Reconciles a server-side conflict "fix" back into the local event the
    /// user actually sees. Without this, /conflicts/intercept only moves the
    /// backend's copy of the event (groupEvents) -- the app would report
    /// success while Calendar/Agenda kept showing the old, conflicting time.
    func applyResolvedConflict(_ response: AuraRemoteConflictInterceptResponse) {
        guard let updated = response.updatedEvent,
              let localEvent = eventFromPayload(updated.payload) else { return }
        let iso = ISO8601DateFormatter()
        guard
            let startRaw = updated.payload["startDate"] ?? response.afterStart,
            let endRaw = updated.payload["endDate"] ?? response.afterEnd,
            let newStart = iso.date(from: startRaw),
            let newEnd = iso.date(from: endRaw)
        else { return }
        var next = localEvent
        next.startDate = newStart
        next.endDate = newEnd
        updateEvent(next)
    }

    func groupListFromPayload(_ payload: [String: String]) -> GroupList? {
        if let rawId = payload["id"],
           let id = UUID(uuidString: rawId),
           let exact = groupLists.first(where: { $0.id == id }) {
            return exact
        }

        let title = payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ??
            payload["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty {
            return nil
        }
        return groupLists.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame })
    }

    func suggestedConflictStart(for eventId: UUID) -> Date? {
        guard let event = events.first(where: { $0.id == eventId }) else { return nil }
        return nextAvailableStart(for: event, excluding: eventId)
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

    func nextAvailableStart(for candidate: CalendarEvent, excluding eventId: UUID? = nil, searchHours: Int = 72) -> Date? {
        guard !candidate.assignedMemberIds.isEmpty else { return candidate.startDate }
        let duration = max(900, candidate.endDate.timeIntervalSince(candidate.startDate))
        var proposedStart = roundedToNextQuarter(candidate.startDate)

        for _ in 0..<(searchHours * 4) {
            var probe = candidate
            probe.startDate = proposedStart
            probe.endDate = proposedStart.addingTimeInterval(duration)
            let clashes = conflictingEvents(for: probe, excluding: eventId)
            if clashes.isEmpty {
                return proposedStart
            }
            if let latestConflictEnd = clashes.map(\.endDate).max() {
                proposedStart = roundedToNextQuarter(latestConflictEnd.addingTimeInterval(60))
            } else {
                proposedStart = proposedStart.addingTimeInterval(15 * 60)
            }
        }
        return nil
    }

    private func roundedToNextQuarter(_ date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = comps.minute ?? 0
        let remainder = minute % 15
        comps.minute = remainder == 0 ? minute : (minute + (15 - remainder))
        comps.second = 0
        return cal.date(from: comps) ?? date
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
            // Whoever imports it into this group is its creator here.
            e.createdByUserId = currentUserId.isEmpty ? nil : currentUserId
            e.ownerName = activeProfileName
            e.modifiedAt = Date()

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
            scheduleReminderIfNeeded(e)
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
        if let evt, !canDelete(evt) { return }
        events.removeAll { $0.id == id }
        recordDeletion([id])
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

    func clearSharedActivity() {
        sharedActivity = []
        saveSharedActivity()
    }

    func logShareInvite(events: [CalendarEvent], permission: SharePermission, via channel: String) {
        guard !events.isEmpty else { return }
        for event in events {
            recordSharedActivity(.init(
                timestamp: Date(),
                sender: activeProfileName,
                eventTitle: event.title,
                action: .inviteSent,
                details: "Shared via \(channel) with \(permission.rawValue.lowercased()) access"
            ))
        }
    }

    func conflictsForSharedEvent(_ event: CalendarEvent) -> [CalendarEvent] {
        conflictingEvents(for: event, excluding: event.id)
    }

    func resolveSharedEventConflict(id: UUID) -> Bool {
        guard let existing = events.first(where: { $0.id == id }) else { return false }
        guard existing.sharePermission == .edit else { return false }
        guard let resolved = suggestedNonConflictingVersion(for: existing) else { return false }
        guard resolved.startDate != existing.startDate || resolved.endDate != existing.endDate else { return false }

        updateEvent(resolved)
        recordSharedActivity(.init(
            timestamp: Date(),
            sender: existing.sharedBy ?? activeProfileName,
            eventTitle: existing.title,
            action: .conflictResolved,
            details: "Moved to \(resolved.startDate.formatted(date: .abbreviated, time: .shortened))"
        ))
        return true
    }

    private func suggestedNonConflictingVersion(for event: CalendarEvent) -> CalendarEvent? {
        let duration = max(1800, event.endDate.timeIntervalSince(event.startDate))
        var candidate = event

        for _ in 0..<24 {
            let conflicts = conflictingEvents(for: candidate, excluding: event.id)
            if conflicts.isEmpty { return candidate }
            guard let latestEnd = conflicts.map(\.endDate).max() else { return candidate }
            candidate.startDate = latestEnd.addingTimeInterval(15 * 60)
            candidate.endDate = candidate.startDate.addingTimeInterval(duration)
        }
        return nil
    }

    // ── Group Members ──────────────────────────────────────
    func loadMembers() {
        // No auto-seeded names here on purpose: this app is used by families,
        // couples, roommates, church groups, travel crews, and study groups alike,
        // so there's no universal default roster that makes sense for everyone.
        // Local profiles start empty; each user adds their own via "Add Local Profile".
        if let d = shared.data(forKey: mKey),
           let v = try? JSONDecoder().decode([GroupMember].self, from: d) {
            members = v
        }
    }

    func saveMembers() {
        if let d = try? JSONEncoder().encode(members) {
            shared.set(d, forKey: mKey)
        }
        if !applyingRemoteSnapshot { queueSyncPush() }
    }

    func addMember(_ m: GroupMember) {
        members.append(m)
        if activeMemberId.isEmpty {
            activeMemberId = m.id.uuidString
        }
        saveMembers()
    }

    func updateMember(_ member: GroupMember) {
        guard let idx = members.firstIndex(where: { $0.id == member.id }) else { return }
        members[idx] = member
        saveMembers()
    }

    func setActiveMember(id: UUID?) {
        activeMemberId = id?.uuidString ?? ""
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

    // ── Shared Group Lists ─────────────────────────────────
    func loadGroupLists() {
        // No auto-seeded list here on purpose, same reasoning as loadMembers():
        // not every group wants a grocery list on day one (a study or travel
        // group might not), so start empty and let people create their own.
        if let d = shared.data(forKey: lKey),
           let v = try? JSONDecoder().decode([GroupList].self, from: d) {
            groupLists = v.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func saveGroupLists() {
        if let d = try? JSONEncoder().encode(groupLists) {
            shared.set(d, forKey: lKey)
        }
        if !applyingRemoteSnapshot { queueSyncPush() }
    }

    func addGroupList(title: String, kind: GroupListKind) {
        addGroupList(title: title, kind: kind, visibility: .family, sharedWithNames: [])
    }

    func addGroupList(title: String, kind: GroupListKind, visibility: VisibilityScope, sharedWithNames: [String]) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let allowed = sharedWithNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let list = GroupList(
            title: clean,
            kind: kind,
            createdAt: Date(),
            items: [],
            ownerName: activeProfileName,
            visibility: visibility,
            sharedWithNames: allowed,
            createdByUserId: currentUserId.isEmpty ? nil : currentUserId,
            modifiedAt: Date()
        )
        groupLists.insert(list, at: 0)
        saveGroupLists()
    }

    func deleteGroupList(id: UUID) {
        guard let list = groupLists.first(where: { $0.id == id }), canDelete(list) else { return }
        groupLists.removeAll { $0.id == id }
        recordDeletion([id] + list.items.map(\.id))
        saveGroupLists()
    }

    func renameGroupList(id: UUID, title: String) -> EditOutcome {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = groupLists.firstIndex(where: { $0.id == id }) else { return .notAllowed }
        guard canEdit(groupLists[i]) else {
            submitProposal(.init(
                kind: .listTitle, targetId: id, targetTitle: groupLists[i].title, proposedTitle: clean,
                proposerUserId: currentUserId, proposerName: activeProfileName,
                targetOwnerUserId: groupLists[i].createdByUserId, targetOwnerName: groupLists[i].ownerName,
                createdAt: Date()
            ))
            return .proposed
        }
        groupLists[i].title = clean
        groupLists[i].modifiedAt = Date()
        saveGroupLists()
        return .applied
    }

    /// Anyone may add to a shared list.
    func addItem(to listId: UUID, item: GroupListItem) {
        guard let i = groupLists.firstIndex(where: { $0.id == listId }) else { return }
        groupLists[i].items.append(stamped(item))
        rememberStore(item.preferredStore)
        saveGroupLists()
    }

    @discardableResult
    func updateItem(listId: UUID, item: GroupListItem) -> EditOutcome {
        guard let i = groupLists.firstIndex(where: { $0.id == listId }),
              let j = groupLists[i].items.firstIndex(where: { $0.id == item.id })
        else { return .notAllowed }
        let original = groupLists[i].items[j]
        guard canEdit(item: original, in: groupLists[i]) else {
            proposeItemChange(kind: .listItem, parentId: listId, original: original, proposed: item, owner: groupLists[i])
            return .proposed
        }
        var next = item
        next.createdByUserId = original.createdByUserId
        next.modifiedAt = Date()
        groupLists[i].items[j] = next
        rememberStore(item.preferredStore)
        saveGroupLists()
        return .applied
    }

    /// Ticking an item done/bought is open to every member.
    func toggleItem(listId: UUID, itemId: UUID) {
        guard let i = groupLists.firstIndex(where: { $0.id == listId }),
              let j = groupLists[i].items.firstIndex(where: { $0.id == itemId })
        else { return }
        groupLists[i].items[j].isDone.toggle()
        groupLists[i].items[j].completedByName = groupLists[i].items[j].isDone ? activeProfileName : nil
        groupLists[i].items[j].boughtAt = groupLists[i].items[j].isDone ? Date() : nil
        groupLists[i].items[j].modifiedAt = Date()
        saveGroupLists()
    }

    func deleteItem(listId: UUID, itemId: UUID) {
        guard let i = groupLists.firstIndex(where: { $0.id == listId }),
              let item = groupLists[i].items.first(where: { $0.id == itemId }),
              canDelete(item: item, in: groupLists[i])
        else { return }
        groupLists[i].items.removeAll { $0.id == itemId }
        recordDeletion([itemId])
        saveGroupLists()
    }

    // ── Group Plans ─────────────────────────────────────────
    func loadGroupPlans() {
        if let d = shared.data(forKey: pKey),
           let v = try? JSONDecoder().decode([GroupPlan].self, from: d) {
            groupPlans = v.sorted { $0.targetDate < $1.targetDate }
        } else {
            groupPlans = []
        }
    }

    func saveGroupPlans() {
        if let d = try? JSONEncoder().encode(groupPlans) {
            shared.set(d, forKey: pKey)
        }
        if !applyingRemoteSnapshot { queueSyncPush() }
    }

    func addGroupPlan(title: String, targetDate: Date, notes: String = "") {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let plan = GroupPlan(
            title: clean, targetDate: targetDate, notes: notes, createdAt: Date(), items: [], ownerName: activeProfileName,
            createdByUserId: currentUserId.isEmpty ? nil : currentUserId, modifiedAt: Date()
        )
        groupPlans.insert(plan, at: 0)
        groupPlans.sort { $0.targetDate < $1.targetDate }
        saveGroupPlans()
    }

    func deleteGroupPlan(id: UUID) {
        guard let plan = groupPlans.first(where: { $0.id == id }), canDelete(plan) else { return }
        groupPlans.removeAll { $0.id == id }
        recordDeletion([id] + plan.items.map(\.id))
        saveGroupPlans()
    }

    func addPlanItem(to planId: UUID, item: GroupListItem) {
        guard let i = groupPlans.firstIndex(where: { $0.id == planId }) else { return }
        groupPlans[i].items.append(stamped(item))
        saveGroupPlans()
    }

    @discardableResult
    func updatePlanItem(planId: UUID, item: GroupListItem) -> EditOutcome {
        guard let i = groupPlans.firstIndex(where: { $0.id == planId }),
              let j = groupPlans[i].items.firstIndex(where: { $0.id == item.id })
        else { return .notAllowed }
        let original = groupPlans[i].items[j]
        guard canEdit(item: original, in: groupPlans[i]) else {
            proposeItemChange(kind: .planItem, parentId: planId, original: original, proposed: item, owner: groupPlans[i])
            return .proposed
        }
        var next = item
        next.createdByUserId = original.createdByUserId
        next.modifiedAt = Date()
        groupPlans[i].items[j] = next
        saveGroupPlans()
        return .applied
    }

    func togglePlanItem(planId: UUID, itemId: UUID) {
        guard let i = groupPlans.firstIndex(where: { $0.id == planId }),
              let j = groupPlans[i].items.firstIndex(where: { $0.id == itemId })
        else { return }
        groupPlans[i].items[j].isDone.toggle()
        groupPlans[i].items[j].completedByName = groupPlans[i].items[j].isDone ? activeProfileName : nil
        groupPlans[i].items[j].modifiedAt = Date()
        saveGroupPlans()
    }

    func deletePlanItem(planId: UUID, itemId: UUID) {
        guard let i = groupPlans.firstIndex(where: { $0.id == planId }),
              let item = groupPlans[i].items.first(where: { $0.id == itemId }),
              canDelete(item: item, in: groupPlans[i])
        else { return }
        groupPlans[i].items.removeAll { $0.id == itemId }
        recordDeletion([itemId])
        saveGroupPlans()
    }

    // ── Ownership ───────────────────────────────────────────
    // Mirrors the server's rules (backend/src/syncMerge.ts), which are what
    // actually enforce them; these only decide what the UI offers.
    var currentUserId: String { serverUserId }

    /// Whether this member created a record. Records from before creator ids
    /// existed fall back to the owner's display name; with no server account
    /// at all, everything on the device is the user's own.
    func isCreator(_ createdByUserId: String?, ownerName: String) -> Bool {
        guard hasServerSession, !currentUserId.isEmpty else { return true }
        if let createdByUserId, !createdByUserId.isEmpty {
            return createdByUserId == currentUserId
        }
        let owner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let me = profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return owner.isEmpty || owner.caseInsensitiveCompare(me) == .orderedSame
    }

    /// The creator has left the active group. Legacy records count as
    /// orphaned when their owner name matches no current member. Unknown
    /// (member list not loaded yet) is treated as "still here".
    func creatorLeft(_ createdByUserId: String?, ownerName: String) -> Bool {
        guard !activeGroupMembers.isEmpty else { return false }
        if let createdByUserId, !createdByUserId.isEmpty {
            return !activeGroupMembers.contains { $0.userId == createdByUserId }
        }
        let owner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !owner.isEmpty && !activeGroupMembers.contains { $0.displayName.caseInsensitiveCompare(owner) == .orderedSame }
    }

    /// The creator edits their own records; once they've left the group the
    /// Owner takes them over, so nothing is left stranded.
    func mayEdit(_ createdByUserId: String?, ownerName: String) -> Bool {
        isCreator(createdByUserId, ownerName: ownerName) || (isActiveGroupOwner && creatorLeft(createdByUserId, ownerName: ownerName))
    }

    func canEdit(_ event: CalendarEvent) -> Bool { mayEdit(event.createdByUserId, ownerName: event.ownerName) }
    func canDelete(_ event: CalendarEvent) -> Bool { canEdit(event) || isActiveGroupOwner }
    func canEdit(_ list: GroupList) -> Bool { mayEdit(list.createdByUserId, ownerName: list.ownerName) }
    func canDelete(_ list: GroupList) -> Bool { canEdit(list) || isActiveGroupOwner }
    func canEdit(_ plan: GroupPlan) -> Bool { mayEdit(plan.createdByUserId, ownerName: plan.ownerName) }
    func canDelete(_ plan: GroupPlan) -> Bool { canEdit(plan) || isActiveGroupOwner }

    /// An item from before creator ids existed belongs to its list's creator.
    func canEdit(item: GroupListItem, in list: GroupList) -> Bool {
        item.createdByUserId != nil ? mayEdit(item.createdByUserId, ownerName: "") : canEdit(list)
    }
    func canDelete(item: GroupListItem, in list: GroupList) -> Bool { canEdit(item: item, in: list) || isActiveGroupOwner }
    func canEdit(item: GroupListItem, in plan: GroupPlan) -> Bool {
        item.createdByUserId != nil ? mayEdit(item.createdByUserId, ownerName: "") : canEdit(plan)
    }
    func canDelete(item: GroupListItem, in plan: GroupPlan) -> Bool { canEdit(item: item, in: plan) || isActiveGroupOwner }

    /// Display name of whoever an edit request would go to.
    func creatorName(ownerName: String) -> String {
        let clean = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "its creator" : clean
    }

    /// Who decides on a request: the creator, or the group's Owner once the
    /// creator has left.
    func deciderName(createdByUserId: String?, ownerName: String) -> String {
        creatorLeft(createdByUserId, ownerName: ownerName) ? "the group owner" : creatorName(ownerName: ownerName)
    }

    private func stamped(_ item: GroupListItem) -> GroupListItem {
        var item = item
        item.createdByUserId = currentUserId.isEmpty ? nil : currentUserId
        item.modifiedAt = Date()
        return item
    }

    // ── Change requests ─────────────────────────────────────
    private func submitProposal(_ proposal: EditProposal) {
        var proposal = proposal
        proposal.modifiedAt = Date()
        // One open request per member per target: a newer suggestion replaces it.
        proposals.removeAll { $0.targetId == proposal.targetId && $0.proposerUserId == currentUserId && $0.status == .pending }
        proposals.append(proposal)
        saveProposals()
    }

    private func proposeEventChange(original: CalendarEvent, proposed: CalendarEvent) {
        submitProposal(.init(
            kind: .event, targetId: original.id, targetTitle: original.title, proposedEvent: proposed,
            proposerUserId: currentUserId, proposerName: activeProfileName,
            targetOwnerUserId: original.createdByUserId, targetOwnerName: original.ownerName,
            createdAt: Date()
        ))
    }

    private func proposeItemChange(kind: EditProposal.Kind, parentId: UUID, original: GroupListItem, proposed: GroupListItem, owner: GroupList) {
        submitProposal(.init(
            kind: kind, targetId: original.id, parentId: parentId, targetTitle: original.name, proposedItem: proposed,
            proposerUserId: currentUserId, proposerName: activeProfileName,
            targetOwnerUserId: original.createdByUserId ?? owner.createdByUserId, targetOwnerName: owner.ownerName,
            createdAt: Date()
        ))
    }

    private func proposeItemChange(kind: EditProposal.Kind, parentId: UUID, original: GroupListItem, proposed: GroupListItem, owner: GroupPlan) {
        submitProposal(.init(
            kind: kind, targetId: original.id, parentId: parentId, targetTitle: original.name, proposedItem: proposed,
            proposerUserId: currentUserId, proposerName: activeProfileName,
            targetOwnerUserId: original.createdByUserId ?? owner.createdByUserId, targetOwnerName: owner.ownerName,
            createdAt: Date()
        ))
    }

    /// Requests waiting on this member's decision.
    var proposalsAwaitingMe: [EditProposal] {
        proposals
            .filter { $0.status == .pending && $0.proposerUserId != currentUserId && isProposalTargetMine($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// This member's own requests, newest first.
    var myProposals: [EditProposal] {
        proposals.filter { $0.proposerUserId == currentUserId }.sorted { $0.createdAt > $1.createdAt }
    }

    func pendingProposal(for targetId: UUID) -> EditProposal? {
        proposals.first { $0.targetId == targetId && $0.proposerUserId == currentUserId && $0.status == .pending }
    }

    private func isProposalTargetMine(_ proposal: EditProposal) -> Bool {
        switch proposal.kind {
        case .event:
            return events.first(where: { $0.id == proposal.targetId }).map(canEdit) ?? false
        case .listTitle:
            return groupLists.first(where: { $0.id == proposal.targetId }).map(canEdit) ?? false
        case .planTitle:
            return groupPlans.first(where: { $0.id == proposal.targetId }).map(canEdit) ?? false
        case .listItem:
            guard let list = groupLists.first(where: { $0.id == proposal.parentId }),
                  let item = list.items.first(where: { $0.id == proposal.targetId }) else { return false }
            return canEdit(item: item, in: list)
        case .planItem:
            guard let plan = groupPlans.first(where: { $0.id == proposal.parentId }),
                  let item = plan.items.first(where: { $0.id == proposal.targetId }) else { return false }
            return canEdit(item: item, in: plan)
        }
    }

    /// Applies the suggested change (as its creator) and marks it approved.
    func approveProposal(id: UUID) {
        guard let p = proposals.first(where: { $0.id == id }), p.status == .pending, isProposalTargetMine(p) else { return }
        switch p.kind {
        case .event:
            if var next = p.proposedEvent, let current = events.first(where: { $0.id == p.targetId }) {
                // The requester can change the details, not who owns it.
                next.id = current.id
                next.ownerName = current.ownerName
                next.createdByUserId = current.createdByUserId
                next.sharePermission = current.sharePermission
                next.sharedBy = current.sharedBy
                updateEvent(next)
            }
        case .listItem:
            if let parentId = p.parentId, var next = p.proposedItem {
                next.id = p.targetId
                updateItem(listId: parentId, item: next)
            }
        case .planItem:
            if let parentId = p.parentId, var next = p.proposedItem {
                next.id = p.targetId
                updatePlanItem(planId: parentId, item: next)
            }
        case .listTitle:
            if let title = p.proposedTitle { _ = renameGroupList(id: p.targetId, title: title) }
        case .planTitle:
            if let title = p.proposedTitle, let i = groupPlans.firstIndex(where: { $0.id == p.targetId }) {
                groupPlans[i].title = title
                groupPlans[i].modifiedAt = Date()
                saveGroupPlans()
            }
        }
        resolveProposal(id: id, status: .approved)
    }

    func declineProposal(id: UUID) {
        guard let p = proposals.first(where: { $0.id == id }), p.status == .pending, isProposalTargetMine(p) else { return }
        resolveProposal(id: id, status: .declined)
    }

    func withdrawProposal(id: UUID) {
        guard let p = proposals.first(where: { $0.id == id }), p.status == .pending, p.proposerUserId == currentUserId else { return }
        resolveProposal(id: id, status: .withdrawn)
    }

    private func resolveProposal(id: UUID, status: EditProposal.Status) {
        guard let i = proposals.firstIndex(where: { $0.id == id }) else { return }
        proposals[i].status = status
        proposals[i].resolvedAt = Date()
        proposals[i].modifiedAt = Date()
        saveProposals()
    }

    // ── Stores ──────────────────────────────────────────────
    /// Adds a store to the group's list (if it isn't there already) and
    /// returns its canonical name.
    @discardableResult
    func addStore(named name: String) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if let existing = groupStores.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            return existing.name
        }
        groupStores.append(.init(name: clean, createdByUserId: currentUserId.isEmpty ? nil : currentUserId, modifiedAt: Date()))
        groupStores.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveGroupStores()
        return clean
    }

    private func rememberStore(_ name: String?) {
        if let name { addStore(named: name) }
    }

    func canDelete(_ store: GroupStore) -> Bool {
        isCreator(store.createdByUserId, ownerName: "") || isActiveGroupOwner
    }

    func deleteStore(id: UUID) {
        guard let store = groupStores.first(where: { $0.id == id }), canDelete(store) else { return }
        groupStores.removeAll { $0.id == id }
        recordDeletion([id])
        saveGroupStores()
    }

    func planFromPayload(_ payload: [String: String]) -> GroupPlan? {
        if let rawId = payload["id"],
           let id = UUID(uuidString: rawId),
           let exact = groupPlans.first(where: { $0.id == id }) {
            return exact
        }
        let title = payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty { return nil }
        return groupPlans.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame })
    }

    // ── Group Activities ───────────────────────────────────
    func loadGroupActivities() {
        if let d = shared.data(forKey: fKey),
           let v = try? JSONDecoder().decode([GroupActivity].self, from: d) {
            groupActivities = v.sorted { $0.date > $1.date }
        }
    }

    func saveGroupActivities() {
        if let d = try? JSONEncoder().encode(groupActivities) {
            shared.set(d, forKey: fKey)
        }
        if !applyingRemoteSnapshot { queueSyncPush() }
    }

    func addActivity(_ a: GroupActivity) {
        groupActivities.insert(a, at: 0)
        if groupActivities.count > 500 { groupActivities = Array(groupActivities.prefix(500)) }
        saveGroupActivities()
    }

    func updateActivity(_ activity: GroupActivity) {
        guard let idx = groupActivities.firstIndex(where: { $0.id == activity.id }) else { return }
        groupActivities[idx] = activity
        groupActivities.sort { $0.date > $1.date }
        saveGroupActivities()
    }

    func deleteActivity(id: UUID) {
        groupActivities.removeAll { $0.id == id }
        recordDeletion([id])
        saveGroupActivities()
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

    var visibleGroupLists: [GroupList] {
        groupLists.filter { canView(visibility: $0.visibility, ownerName: $0.ownerName, sharedWithNames: $0.sharedWithNames) }
    }

    var visibleGroupActivities: [GroupActivity] {
        groupActivities.filter { canView(visibility: $0.visibility, ownerName: $0.ownerName, sharedWithNames: $0.sharedWithNames) }
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
           let session = try? JSONDecoder().decode(LiveGroupActivitySession.self, from: d) {
            activeActivitySession = session
        }
    }

    func startLiveActivity(kind: GroupActivityKind, notes: String, participantIds: [UUID], visibility: VisibilityScope, sharedWithNames: [String]) {
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
        guard let snapshot = visibleGroupStepSnapshots.first(where: {
            $0.ownerName.caseInsensitiveCompare(member.name) == .orderedSame && Calendar.current.isDateInToday($0.date)
        }) else { return nil }
        return snapshot.steps
    }

    func activityStepTotal(_ activity: GroupActivity) -> Int {
        activity.participantIds.compactMap { visibleSteps(for: $0) }.reduce(0, +)
    }

    var visibleGroupStepSnapshots: [GroupStepSnapshot] {
        groupStepSnapshots.filter { canView(visibility: $0.visibility, ownerName: $0.ownerName, sharedWithNames: $0.sharedWithNames) }
    }

    func updateBackendBaseURL(_ value: String) {
        backendBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if backendBaseURL.isEmpty && backendAuthToken.isEmpty {
            syncStatus = currentGroupCode.isEmpty ? "Sync disabled" : "Group linked"
        }
        objectWillChange.send()
    }

    func clearServerSession() {
        // Stop this device getting the signed-out account's pushes. Best effort:
        // an expired session can't unregister, and the server drops the token
        // once Apple reports it dead or another account registers it.
        if let pushToken = UserDefaults.standard.string(forKey: "aura.apnsToken"), hasServerSession {
            let baseURL = currentBackendBaseURL
            let authToken = backendAuthToken
            Task {
                _ = try? await AuraServerSyncEngine.shared.unregisterDevice(baseURL: baseURL, token: authToken, deviceToken: pushToken)
            }
        }
        backendAuthToken = ""
        backendAccountEmail = ""
        backendGroupId = ""
        backendStoredGroupName = ""
        changeActiveGroup(to: "")
        serverAccountEmail = ""
        serverGroupName = ""
        serverMembershipRole = ""
        serverIsAdmin = false
        serverUserId = ""
        storedUserId = ""
        serverGroups = []
        serverGroupConflictHistoryEntries = []
        personalMasterCalendarItems = []
        personalTaskItems = []
        personalPlanItems = []
        personalRoutineItems = []
        personalConflictItems = []
        syncStatus = currentGroupCode.isEmpty ? "Sync disabled" : "Group linked"
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
                // The fallback string alone ("Server sync pull failed") gave no
                // way to tell a 403/404 from a decoding error from a timeout --
                // every distinct failure looked identical in the UI, which is
                // exactly what made this genuinely hard to diagnose remotely.
                if let detail = serverError.errorDescription, !detail.isEmpty {
                    syncStatus = "\(fallbackStatus): \(detail)"
                } else {
                    syncStatus = fallbackStatus
                }
                return serverError
            }
        }
        syncStatus = "\(fallbackStatus): \(error.localizedDescription)"
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

    /// Tells the server where to push this account's group updates. Runs on
    /// every sign-in and whenever APNs issues a token.
    func registerPushTokenIfPossible() async {
        guard hasServerSession, let token = UserDefaults.standard.string(forKey: "aura.apnsToken") else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        _ = try? await AuraServerSyncEngine.shared.registerDevice(baseURL: currentBackendBaseURL, token: backendAuthToken, deviceToken: token, environment: environment)
    }

    func requestPasswordReset(email: String) async -> Result<Void, Error> {
        do {
            _ = try await AuraServerSyncEngine.shared.requestPasswordReset(
                baseURL: currentBackendBaseURL,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Sets the new password and signs in with it.
    func resetPassword(email: String, code: String, newPassword: String) async -> Result<Void, Error> {
        do {
            let response = try await AuraServerSyncEngine.shared.resetPassword(
                baseURL: currentBackendBaseURL,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                newPassword: newPassword
            )
            applyAuth(response)
            syncStatus = "Signed in"
            await refreshServerContext()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func refreshServerContext() async {
        guard hasServerSession else { return }
        do {
            let me = try await AuraServerSyncEngine.shared.me(baseURL: currentBackendBaseURL, token: backendAuthToken)
            backendAccountEmail = me.user.email
            serverAccountEmail = me.user.email
            profileDisplayName = me.user.displayName
            serverUserId = me.user.id
            storedUserId = me.user.id
            await registerPushTokenIfPossible()
            serverMembershipRole = me.membership?.role ?? ""
            serverIsAdmin = me.isAdmin ?? false

            if me.membership != nil,
               let household = try? await AuraServerSyncEngine.shared.currentHousehold(baseURL: currentBackendBaseURL, token: backendAuthToken) {
                backendGroupId = household.household?.id ?? ""
                backendStoredGroupName = household.household?.name ?? ""
                serverGroupName = backendStoredGroupName
                if let code = household.household?.code {
                    householdCode = code
                }
            }
            await refreshServerGroups()
            await refreshServerAdminData()
            syncStatus = hasServerGroup ? "Server workspace connected" : "Signed in · no active group yet"
        } catch {
            _ = mapServerError(error, fallbackStatus: "Server refresh failed")
        }
    }

    func refreshServerGroups() async {
        guard hasServerSession else {
            serverGroups = []
            changeActiveGroup(to: "")
            return
        }

        do {
            let response = try await AuraServerSyncEngine.shared.groups(baseURL: currentBackendBaseURL, token: backendAuthToken)
            serverGroups = response.groups

            if let active = response.groups.first(where: { $0.group.id == activeGroupId }) {
                serverMembershipRole = active.membership.role
                backendGroupId = active.group.id
                backendStoredGroupName = active.group.name
                serverGroupName = active.group.name
                householdCode = active.group.code
                syncActiveGroupNameToWidget(active.group.name)
            } else if let first = response.groups.first {
                changeActiveGroup(to: first.group.id)
                serverMembershipRole = first.membership.role
                backendGroupId = first.group.id
                backendStoredGroupName = first.group.name
                serverGroupName = first.group.name
                householdCode = first.group.code
                syncActiveGroupNameToWidget(first.group.name)
            } else {
                changeActiveGroup(to: "")
                serverMembershipRole = ""
                syncActiveGroupNameToWidget("")
            }
        } catch {
            _ = mapServerError(error, fallbackStatus: "Group refresh failed")
        }
    }

    func refreshPersonalLayer() async {
        guard hasServerSession else {
            personalMasterCalendarItems = []
            personalTaskItems = []
            personalPlanItems = []
            personalRoutineItems = []
            personalConflictItems = []
            return
        }

        isLoadingPersonalLayer = true
        defer { isLoadingPersonalLayer = false }

        do {
            async let calendar = AuraServerSyncEngine.shared.personalMasterCalendar(baseURL: currentBackendBaseURL, token: backendAuthToken)
            async let tasks = AuraServerSyncEngine.shared.personalTasks(baseURL: currentBackendBaseURL, token: backendAuthToken)
            async let plans = AuraServerSyncEngine.shared.personalPlans(baseURL: currentBackendBaseURL, token: backendAuthToken)
            async let routines = AuraServerSyncEngine.shared.personalRoutines(baseURL: currentBackendBaseURL, token: backendAuthToken)
            async let conflicts = AuraServerSyncEngine.shared.conflictCheck(baseURL: currentBackendBaseURL, token: backendAuthToken)

            let calendarValue = try await calendar
            let tasksValue = try await tasks
            let plansValue = try await plans
            let routinesValue = try await routines
            let conflictsValue = try await conflicts

            personalMasterCalendarItems = calendarValue.items
            personalTaskItems = tasksValue.items
            personalPlanItems = plansValue.items
            personalRoutineItems = routinesValue.items
            personalConflictItems = conflictsValue.conflicts
        } catch {
            _ = mapServerError(error, fallbackStatus: "Personal layer refresh failed")
        }
    }

    func interceptServerConflict(
        action: String,
        leftEventId: String,
        rightEventId: String,
        preferredEventId: String? = nil
    ) async -> Result<AuraRemoteConflictInterceptResponse, Error> {
        guard hasServerSession else {
            return .failure(AuraServerError.requestFailed("Server session required."))
        }
        do {
            let response = try await AuraServerSyncEngine.shared.conflictIntercept(
                baseURL: currentBackendBaseURL,
                token: backendAuthToken,
                action: action,
                leftEventId: leftEventId,
                rightEventId: rightEventId,
                preferredEventId: preferredEventId
            )
            return .success(response)
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Conflict action failed"))
        }
    }

    func refreshServerAdminData() async {
        guard hasServerSession, isServerOwner else {
            serverGroupConflictHistoryEntries = []
            return
        }
        do {
            if !activeServerGroupId.isEmpty {
                let conflicts = try await AuraServerSyncEngine.shared.groupConflictHistory(
                    baseURL: currentBackendBaseURL,
                    token: backendAuthToken,
                    groupId: activeServerGroupId
                )
                serverGroupConflictHistoryEntries = conflicts.entries
            } else {
                serverGroupConflictHistoryEntries = []
            }
        } catch {
            _ = mapServerError(error, fallbackStatus: "Admin refresh failed")
        }
    }

    func refreshActiveGroupAdminData() async {
        guard hasServerSession, !activeServerGroupId.isEmpty else {
            activeGroupMemberRecords = []
            activeGroupAuditEntries = []
            return
        }
        let groupId = activeServerGroupId
        isLoadingActiveGroupAdmin = true
        defer { isLoadingActiveGroupAdmin = false }
        do {
            let members = try await AuraServerSyncEngine.shared.groupMembers(baseURL: currentBackendBaseURL, token: backendAuthToken, groupId: groupId)
            activeGroupMemberRecords = members.members
            let audit = try await AuraServerSyncEngine.shared.groupAudit(baseURL: currentBackendBaseURL, token: backendAuthToken, groupId: groupId)
            activeGroupAuditEntries = audit.entries
        } catch {
            _ = mapServerError(error, fallbackStatus: "Group admin refresh failed")
        }
    }

    func updateActiveGroupMemberRole(userId: String, role: String) async -> Result<Void, Error> {
        guard hasServerSession, isActiveGroupOwner else {
            return .failure(AuraServerError.requestFailed("Owner access required."))
        }
        do {
            _ = try await AuraServerSyncEngine.shared.groupUpdateMemberRole(baseURL: currentBackendBaseURL, token: backendAuthToken, groupId: activeServerGroupId, userId: userId, role: role)
            await refreshActiveGroupAdminData()
            syncStatus = "Member role updated"
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Role update failed"))
        }
    }

    func removeActiveGroupMember(userId: String) async -> Result<Void, Error> {
        guard hasServerSession, isActiveGroupOwner else {
            return .failure(AuraServerError.requestFailed("Owner access required."))
        }
        do {
            _ = try await AuraServerSyncEngine.shared.groupRemoveMember(baseURL: currentBackendBaseURL, token: backendAuthToken, groupId: activeServerGroupId, userId: userId)
            await refreshActiveGroupAdminData()
            syncStatus = "Member removed"
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Remove member failed"))
        }
    }

    func transferActiveGroupOwnership(to userId: String) async -> Result<Void, Error> {
        guard hasServerSession, isActiveGroupOwner else {
            return .failure(AuraServerError.requestFailed("Owner access required."))
        }
        do {
            _ = try await AuraServerSyncEngine.shared.groupTransferOwner(baseURL: currentBackendBaseURL, token: backendAuthToken, groupId: activeServerGroupId, userId: userId)
            await refreshServerGroups()
            await refreshActiveGroupAdminData()
            syncStatus = "Ownership transferred"
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Transfer owner failed"))
        }
    }

    func regenerateActiveGroupCode() async -> Result<String, Error> {
        guard hasServerSession, isActiveGroupOwner else {
            return .failure(AuraServerError.requestFailed("Owner access required."))
        }
        do {
            let response = try await AuraServerSyncEngine.shared.groupRegenerateCode(baseURL: currentBackendBaseURL, token: backendAuthToken, groupId: activeServerGroupId)
            householdCode = response.group.code
            await refreshServerGroups()
            await refreshActiveGroupAdminData()
            syncStatus = "Join code regenerated"
            return .success(response.group.code)
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Regenerate code failed"))
        }
    }

    func renameGroup(groupId: String, name: String) async -> Result<Void, Error> {
        guard hasServerSession else {
            return .failure(AuraServerError.requestFailed("Sign in before renaming a group."))
        }
        guard serverGroups.first(where: { $0.group.id == groupId })?.membership.role == "Owner" else {
            return .failure(AuraServerError.requestFailed("Only the group's owner can rename it."))
        }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return .failure(AuraServerError.requestFailed("Group name cannot be empty."))
        }
        do {
            _ = try await AuraServerSyncEngine.shared.renameGroup(baseURL: currentBackendBaseURL, token: backendAuthToken, groupId: groupId, name: clean)
            await refreshServerGroups()
            if groupId == activeServerGroupId {
                syncActiveGroupNameToWidget(clean)
            }
            syncStatus = "Group renamed"
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Rename group failed"))
        }
    }

    func createServerHousehold(name: String) async -> Result<String, Error> {
        return await createServerGroup(name: name, type: "Family")
    }

    func createServerGroup(name: String, type: String) async -> Result<String, Error> {
        guard hasServerSession else {
            return .failure(AuraServerError.requestFailed("Sign in before creating a group."))
        }
        do {
            let response = try await AuraServerSyncEngine.shared.createGroup(
                baseURL: currentBackendBaseURL,
                token: backendAuthToken,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type
            )
            await refreshServerGroups()
            setActiveServerGroup(id: response.group.id)
            syncStatus = "Group ready"
            return .success(response.group.code)
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Create group failed"))
        }
    }

    func joinServerHousehold(code: String) async -> Result<Void, Error> {
        return await joinServerGroup(code: code)
    }

    func joinServerGroup(code: String) async -> Result<Void, Error> {
        guard hasServerSession else {
            return .failure(AuraServerError.requestFailed("Sign in before joining a group."))
        }
        do {
            let response = try await AuraServerSyncEngine.shared.joinGroup(
                baseURL: currentBackendBaseURL,
                token: backendAuthToken,
                code: code.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await refreshServerGroups()
            setActiveServerGroup(id: response.group.id)
            syncStatus = "Joined \(response.group.name)"
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Join group failed"))
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

    func deleteServerAccount(password: String) async -> Result<Void, Error> {
        guard hasServerSession else {
            return .failure(AuraServerError.requestFailed("Sign in before deleting your account."))
        }
        guard !password.isEmpty else {
            return .failure(AuraServerError.requestFailed("Enter your password to confirm."))
        }
        do {
            _ = try await AuraServerSyncEngine.shared.deleteAccount(
                baseURL: currentBackendBaseURL,
                token: backendAuthToken,
                password: password
            )
            await MainActor.run {
                clearServerSession()
            }
            return .success(())
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Account deletion failed"))
        }
    }

    func exportAccountData() async -> Result<URL, Error> {
        guard hasServerSession else {
            return .failure(AuraServerError.requestFailed("Sign in before exporting your data."))
        }
        do {
            let data = try await AuraServerSyncEngine.shared.exportAccountData(
                baseURL: currentBackendBaseURL,
                token: backendAuthToken
            )
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let fileName = "Aurenda-export-\(df.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return .success(url)
        } catch {
            return .failure(mapServerError(error, fallbackStatus: "Export failed"))
        }
    }

    private func applyAuth(_ response: AuraRemoteAuthResponse) {
        backendAuthToken = response.token
        backendAccountEmail = response.user.email
        serverAccountEmail = response.user.email
        profileDisplayName = response.user.displayName
        serverUserId = response.user.id
        storedUserId = response.user.id
        objectWillChange.send()
    }

    func queueSyncPush() {
        let canSync = hasServerGroup
        guard canSync else { return }
        hasPendingPush = true
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.pushSnapshot()
        }
    }

    func forceSyncNow() {
        let canSync = hasServerGroup
        guard canSync else { return }
        Task { [weak self] in
            await self?.pushSnapshot()
            await self?.pullSnapshot()
        }
    }

    @MainActor
    func refreshHomeDashboard() async {
        if hasServerSession {
            await refreshServerContext()
            await refreshPersonalLayer()
        }
        await pullSnapshot()
        refreshDailyStepsIfEnabled(force: true)
    }

    private func startPeriodicPull() {
        periodicPullTask?.cancel()
        periodicPullTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let interval: UInt64 = self.hasServerGroup ? 6_000_000_000 : 15_000_000_000
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
            groupLists: groupLists,
            groupActivities: groupActivities,
            stepSnapshots: groupStepSnapshots,
            groupPlans: groupPlans,
            stores: groupStores,
            proposals: proposals,
            deletedIds: deletedIds
        )
    }

    // Per-group sync bookkeeping, keyed by group so switching groups never
    // compares one group's version against another's.
    private var snapshotVersion: String? {
        get { UserDefaults.standard.string(forKey: "aura.snapshotVersion.\(activeServerGroupId)") }
        set { UserDefaults.standard.set(newValue, forKey: "aura.snapshotVersion.\(activeServerGroupId)") }
    }

    private var lastSyncedAt: Date {
        get { UserDefaults.standard.object(forKey: "aura.lastSyncedAt.\(activeServerGroupId)") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "aura.lastSyncedAt.\(activeServerGroupId)") }
    }

    /// Uploads this device's copy. The server merges it record by record
    /// (enforcing who may change or delete what) and returns the merged
    /// result, which is folded back in here.
    @MainActor
    private func pushSnapshot() async {
        guard hasServerGroup else {
            // CloudKit fallback disabled: the app ships with no iCloud/CloudKit
            // entitlement, so server sync is the only supported path.
            return
        }
        let groupId = activeServerGroupId
        hasPendingPush = false
        do {
            let response = try await AuraServerSyncEngine.shared.uploadSnapshot(baseURL: currentBackendBaseURL, token: backendAuthToken, groupId: groupId, payload: snapshotPayload())
            // The active group changed while this was in flight; its response
            // belongs to the previous group's data.
            guard groupId == activeServerGroupId else { return }
            if let members = response.groupMembers { activeGroupMembers = members }
            if let record = response.snapshot {
                applyServerSnapshot(record)
            }
            syncStatus = "Server synced just now"
        } catch {
            hasPendingPush = true
            _ = mapServerError(error, fallbackStatus: "Server sync upload failed")
        }
    }

    @MainActor
    private func pullSnapshot() async {
        guard hasServerGroup else { return }
        // Unsent local changes go up first: the server's merged reply then
        // carries everyone else's changes too, and nothing local is at risk of
        // being merged away before it was ever sent.
        if hasPendingPush {
            await pushSnapshot()
            return
        }
        // First sync of a group on this build: upload everything first so the
        // server's merge can recover records only this device still holds
        // (members' uploads used to overwrite each other wholesale).
        let recoveryKey = "aura.recoveryPushed.\(activeServerGroupId)"
        if !UserDefaults.standard.bool(forKey: recoveryKey) {
            await pushSnapshot()
            if !hasPendingPush {
                UserDefaults.standard.set(true, forKey: recoveryKey)
            }
            return
        }
        let groupId = activeServerGroupId
        do {
            let response = try await AuraServerSyncEngine.shared.downloadSnapshot(baseURL: currentBackendBaseURL, token: backendAuthToken, groupId: groupId, since: snapshotVersion)
            guard groupId == activeServerGroupId else { return }
            if let members = response.groupMembers { activeGroupMembers = members }
            guard response.unchanged != true, let record = response.snapshot else { return }
            applyServerSnapshot(record)
            syncStatus = "Server updated from \(record.updatedBy)"
        } catch {
            _ = mapServerError(error, fallbackStatus: "Server sync pull failed")
        }
    }

    /// Folds the server's copy into local state: tombstoned records go, the
    /// newer of each pair wins, and a record only this device has is kept if
    /// it's this member's own or changed since the last sync (not yet
    /// uploaded) -- anyone else's that the server no longer returns was hidden
    /// from this member and is dropped.
    @MainActor
    private func applyServerSnapshot(_ record: AuraRemoteSnapshotRecord) {
        let remote = record.payload
        let syncedBefore = lastSyncedAt
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        var tombstones = deletedIds.merging(remote.deletedIds) { max($0, $1) }
        tombstones = tombstones.filter { $0.value > cutoff }
        let isDeleted: (UUID) -> Bool = { tombstones[$0.uuidString] != nil }

        func merged<T: Identifiable>(
            _ local: [T],
            _ incoming: [T],
            modified: (T) -> Date?,
            keepLocalOnly: (T) -> Bool,
            combine: (T, T) -> T = { _, remote in remote }
        ) -> [T] where T.ID == UUID {
            let localById = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var result: [T] = []
            var seen = Set<UUID>()
            for remoteRecord in incoming where !isDeleted(remoteRecord.id) {
                seen.insert(remoteRecord.id)
                if let localRecord = localById[remoteRecord.id],
                   (modified(localRecord) ?? .distantPast) > (modified(remoteRecord) ?? .distantPast) {
                    result.append(combine(remoteRecord, localRecord))
                } else if let localRecord = localById[remoteRecord.id] {
                    result.append(combine(localRecord, remoteRecord))
                } else {
                    result.append(remoteRecord)
                }
            }
            for localRecord in local where !seen.contains(localRecord.id) && !isDeleted(localRecord.id) && keepLocalOnly(localRecord) {
                result.append(localRecord)
            }
            return result
        }

        let unsynced: (Date?) -> Bool = { ($0 ?? .distantPast) > syncedBefore }
        let mergeItems: ([GroupListItem], [GroupListItem]) -> [GroupListItem] = { local, incoming in
            merged(local, incoming, modified: { $0.modifiedAt }, keepLocalOnly: { unsynced($0.modifiedAt) })
        }

        applyingRemoteSnapshot = true
        events = merged(events, remote.events, modified: { $0.modifiedAt }, keepLocalOnly: { [unowned self] in
            self.isCreator($0.createdByUserId, ownerName: $0.ownerName) || unsynced($0.modifiedAt)
        }).sorted { $0.startDate < $1.startDate }
        groupLists = merged(groupLists, remote.groupLists, modified: { $0.modifiedAt }, keepLocalOnly: { [unowned self] in
            self.isCreator($0.createdByUserId, ownerName: $0.ownerName) || unsynced($0.modifiedAt)
        }, combine: { older, newer in
            var list = newer
            list.items = mergeItems(older.items, newer.items)
            return list
        }).sorted { $0.createdAt > $1.createdAt }
        groupPlans = merged(groupPlans, remote.groupPlans, modified: { $0.modifiedAt }, keepLocalOnly: { [unowned self] in
            self.isCreator($0.createdByUserId, ownerName: $0.ownerName) || unsynced($0.modifiedAt)
        }, combine: { older, newer in
            var plan = newer
            plan.items = mergeItems(older.items, newer.items)
            return plan
        }).sorted { $0.targetDate < $1.targetDate }
        groupStores = merged(groupStores, remote.stores, modified: { $0.modifiedAt }, keepLocalOnly: { unsynced($0.modifiedAt) })
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        proposals = merged(proposals, remote.proposals, modified: { $0.modifiedAt }, keepLocalOnly: { [unowned self] in
            $0.proposerUserId == self.currentUserId && $0.status == .pending && unsynced($0.modifiedAt)
        })
        // Not owned and not timestamped: the server's copy wins, plus
        // anything local it hasn't received yet.
        categories = merged(categories, remote.categories, modified: { _ in nil }, keepLocalOnly: { _ in true })
        members = merged(members, remote.members, modified: { _ in nil }, keepLocalOnly: { _ in true })
        groupActivities = merged(groupActivities, remote.groupActivities, modified: { _ in nil }, keepLocalOnly: { _ in true })
            .sorted { $0.date > $1.date }
        groupStepSnapshots = merged(groupStepSnapshots, remote.stepSnapshots, modified: { $0.updatedAt }, keepLocalOnly: { _ in true })
            .sorted { $0.updatedAt > $1.updatedAt }
        deletedIds = tombstones

        saveCats()
        saveEvents()
        saveMembers()
        saveGroupLists()
        saveGroupPlans()
        saveGroupActivities()
        saveGroupStepSnapshots()
        saveGroupStores()
        saveProposals()
        saveDeletedIds()
        applyingRemoteSnapshot = false

        snapshotVersion = record.updatedAt
        lastSyncedAt = Date()
        rebuildScheduledNotifications()
    }

    // ── Per-group local data ────────────────────────────────
    // The working keys (aura.events etc., which the widget also reads) always
    // hold the active group's data. Switching groups parks the old group's
    // copy under keys suffixed with its id and loads the new group's -- the
    // app used to keep one shared copy, so after a switch its next upload
    // pushed the previous group's events into the new group.
    private var groupScopedKeys: [String] { [eKey, lKey, pKey, fKey, sKey, storesKey, proposalsKey, deletedKey] }

    private func switchLocalGroupData(from oldGroupId: String, to newGroupId: String) {
        guard oldGroupId != newGroupId else { return }
        syncDebounceTask?.cancel()
        if hasPendingPush, !oldGroupId.isEmpty {
            // Pending edits belong to the old group; they're parked with it and
            // go up the next time it's active.
            UserDefaults.standard.set(true, forKey: "aura.pendingPush.\(oldGroupId)")
        }
        let defaults = shared
        if !oldGroupId.isEmpty {
            for key in groupScopedKeys {
                defaults.set(defaults.data(forKey: key), forKey: "\(key).\(oldGroupId)")
            }
        }
        for key in groupScopedKeys {
            if !newGroupId.isEmpty, let parked = defaults.data(forKey: "\(key).\(newGroupId)") {
                defaults.set(parked, forKey: key)
            } else if !oldGroupId.isEmpty {
                // Never seen this group here (or leaving all groups): start
                // empty rather than carrying the previous group's data over.
                defaults.removeObject(forKey: key)
            }
        }
        events = []
        activeGroupMembers = []
        groupLists = []
        groupPlans = []
        groupActivities = []
        groupStepSnapshots = []
        groupStores = []
        proposals = []
        deletedIds = [:]
        loadEvents()
        loadGroupLists()
        loadGroupPlans()
        loadGroupActivities()
        loadGroupStepSnapshots()
        loadGroupStores()
        loadProposals()
        loadDeletedIds()
        hasPendingPush = UserDefaults.standard.bool(forKey: "aura.pendingPush.\(newGroupId)")
        UserDefaults.standard.removeObject(forKey: "aura.pendingPush.\(newGroupId)")
        rebuildScheduledNotifications()
        Task { @MainActor [weak self] in
            await self?.pullSnapshot()
        }
    }

    /// The single place the active group changes, so its local data always
    /// moves with it.
    private func changeActiveGroup(to newGroupId: String) {
        let previous = activeGroupId
        activeGroupId = newGroupId
        switchLocalGroupData(from: previous, to: newGroupId)
    }

    private func loadCodable<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = shared.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func saveCodable<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            shared.set(data, forKey: key)
        }
    }

    func loadGroupStores() {
        groupStores = loadCodable([GroupStore].self, key: storesKey) ?? []
    }

    func saveGroupStores() {
        saveCodable(groupStores, key: storesKey)
        if !applyingRemoteSnapshot { queueSyncPush() }
    }

    func loadProposals() {
        proposals = loadCodable([EditProposal].self, key: proposalsKey) ?? []
    }

    func saveProposals() {
        saveCodable(proposals, key: proposalsKey)
        if !applyingRemoteSnapshot { queueSyncPush() }
    }

    func loadDeletedIds() {
        deletedIds = loadCodable([String: Date].self, key: deletedKey) ?? [:]
    }

    func saveDeletedIds() {
        saveCodable(deletedIds, key: deletedKey)
    }

    private func recordDeletion(_ ids: [UUID]) {
        let now = Date()
        for id in ids {
            deletedIds[id.uuidString] = now
        }
        saveDeletedIds()
    }

    func loadGroupStepSnapshots() {
        if let d = shared.data(forKey: sKey),
           let v = try? JSONDecoder().decode([GroupStepSnapshot].self, from: d) {
            groupStepSnapshots = v.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func saveGroupStepSnapshots() {
        if let d = try? JSONEncoder().encode(groupStepSnapshots) {
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
        if let idx = groupStepSnapshots.firstIndex(where: {
            $0.ownerName.caseInsensitiveCompare(activeProfileName) == .orderedSame &&
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }) {
            groupStepSnapshots[idx].steps = steps
            groupStepSnapshots[idx].visibility = visibility
            groupStepSnapshots[idx].sharedWithNames = sharedNames
            groupStepSnapshots[idx].updatedAt = Date()
        } else {
            groupStepSnapshots.insert(
                .init(ownerName: activeProfileName, date: today, steps: steps, visibility: visibility, sharedWithNames: sharedNames, updatedAt: Date()),
                at: 0
            )
        }
        saveGroupStepSnapshots()
    }
}
