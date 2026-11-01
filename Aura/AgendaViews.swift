import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

// MARK: - Agenda View

struct AgendaView: View {
    @State private var eventPendingDelete: CalendarEvent? = nil
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var shareManager: ShareManager
    @Binding var showCreate: Bool
    @State private var q = ""
    @State private var selected: CalendarEvent?
    @State private var editingEvent: CalendarEvent?
    @State private var showShareAgenda = false
    @State private var scrollOffset: CGFloat = 0
    @Namespace private var eventHeroNamespace

    var todayEvents: [CalendarEvent] {
        store.events(for: Date()).sorted { $0.startDate < $1.startDate }
    }
    var nextTodayEvent: CalendarEvent? {
        todayEvents.first { $0.startDate >= Date() } ?? todayEvents.first
    }

    // Agenda is a forward-looking list -- an event that's already over has
    // nothing to do with "upcoming" and shouldn't sit mixed in with it.
    // Search still reaches past events, since deliberately looking something
    // up is a different intent than browsing what's ahead.
    var filtered: [CalendarEvent] {
        q.isEmpty
            ? store.visibleEvents.filter { $0.endDate >= Calendar.current.startOfDay(for: Date()) }
            : store.visibleEvents.filter {
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

    var conflicts: [AgendaConflict] {
        guard q.isEmpty else { return [] }
        var result: [AgendaConflict] = []
        for (_, evts) in grouped {
            let sorted = evts.filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
            for i in 0..<sorted.count {
                for j in (i + 1)..<sorted.count {
                    let a = sorted[i], b = sorted[j]
                    if a.startDate < b.endDate && b.startDate < a.endDate {
                        result.append(AgendaConflict(first: a, second: b))
                    }
                }
            }
        }
        return result
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
                AuraAtmosphericBackground()
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

                            if !conflicts.isEmpty {
                                AgendaConflictsCard(conflicts: conflicts) { event in
                                    AuraHaptics.tap(.light)
                                    withAnimation(AuraMotion.spring) { selected = event }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
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
                                            .contextMenu {
                                                Button {
                                                    AuraHaptics.tap(.light)
                                                    withAnimation(AuraMotion.spring) { selected = e }
                                                } label: {
                                                    Label("View Details", systemImage: "eye.fill")
                                                }
                                                Button {
                                                    AuraHaptics.tap(.light)
                                                    editingEvent = e
                                                } label: {
                                                    Label(store.canEdit(e) ? "Edit" : "Suggest Changes", systemImage: "pencil")
                                                }
                                                Button {
                                                    AuraHaptics.success()
                                                    var copy = e
                                                    copy.id = UUID()
                                                    copy.title = "\(e.title) Copy"
                                                    store.addEvent(copy)
                                                } label: {
                                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                                }
                                                if store.canDelete(e) {
                                                    Button(role: .destructive) {
                                                        AuraHaptics.warning()
                                                        eventPendingDelete = e
                                                    } label: {
                                                        Label("Delete", systemImage: "trash")
                                                    }
                                                }
                                            }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                if store.canDelete(e) {
                                                    Button(role: .destructive) {
                                                        AuraHaptics.warning()
                                                        eventPendingDelete = e
                                                    } label: {
                                                        Label("Delete", systemImage: "trash")
                                                    }
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
            .navigationTitle("Agenda")
            .navigationBarTitleDisplayMode(.large)
            .auraTabChrome()
            .alert("Delete Event", isPresented: Binding(
                get: { eventPendingDelete != nil },
                set: { if !$0 { eventPendingDelete = nil } }
            ), presenting: eventPendingDelete) { e in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    AuraHaptics.warning()
                    withAnimation(AuraMotion.smooth) { store.deleteEvent(id: e.id) }
                }
            } message: { e in
                Text("Delete \"\(e.title)\" for everyone in the group? This can't be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showShareAgenda = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityLabel("Share")
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
        .sheet(item: $editingEvent) { event in
            CreateEventView(
                isPresented: Binding(get: { true }, set: { _ in editingEvent = nil }),
                editing: event
            )
            .environmentObject(store)
        }
    }
}

struct AgendaConflict: Identifiable {
    let id = UUID()
    let first: CalendarEvent
    let second: CalendarEvent

    var severityLabel: String {
        let overlapStart = max(first.startDate, second.startDate)
        let overlapEnd = min(first.endDate, second.endDate)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        let shorterDuration = min(
            first.endDate.timeIntervalSince(first.startDate),
            second.endDate.timeIntervalSince(second.startDate)
        )
        guard shorterDuration > 0 else { return "Overlap" }
        return overlap / shorterDuration >= 0.5 ? "High" : "Medium"
    }

    var severityColor: Color {
        switch severityLabel {
        case "High": return .red
        case "Medium": return .orange
        default: return .yellow
        }
    }
}

struct AgendaConflictsCard: View {
    let conflicts: [AgendaConflict]
    var onSelect: (CalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .auraFont(size: 13, weight: .bold)
                    .foregroundColor(.orange)
                Text("\(conflicts.count) scheduling conflict\(conflicts.count == 1 ? "" : "s") today")
                    .auraFont(size: 13, weight: .bold)
            }
            VStack(spacing: 8) {
                ForEach(conflicts.prefix(5)) { conflict in
                    Button {
                        onSelect(conflict.first)
                    } label: {
                        HStack(spacing: 10) {
                            Text(conflict.severityLabel)
                                .auraFont(size: 10, weight: .bold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(conflict.severityColor.opacity(0.2), in: Capsule())
                                .foregroundColor(conflict.severityColor)
                            Text("\(conflict.first.title) overlaps \(conflict.second.title)")
                                .auraFont(size: 12, weight: .medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .auraFont(size: 10, weight: .semibold)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.orange.opacity(0.25), lineWidth: 1))
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
                        .auraFont(size: 17, weight: .bold)
                        .foregroundColor(.white)
                    Text("\(totalToday) event\(totalToday == 1 ? "" : "s") planned")
                        .auraFont(size: 12, weight: .medium)
                        .foregroundColor(.white.opacity(0.88))
                }
                Spacer()
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("Add")
                        .auraFont(size: 14, weight: .bold)
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
            }
            if let e = nextEvent {
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill")
                        .auraFont(size: 12, weight: .semibold)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next: \(e.title)")
                            .auraFont(size: 13, weight: .semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(timeLabel(e))
                            .auraFont(size: 11, weight: .medium)
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
    @EnvironmentObject var store: EventStore
    @EnvironmentObject var shareManager: ShareManager
    @Environment(\.dismiss) var dismiss

    let title: String
    let subtitle: String
    let events: [CalendarEvent]

    @AppStorage("profileDisplayName") private var storedDisplayName = ""
    @State private var senderName = ""
    @State private var permission: SharePermission = .edit
    @State private var shareNotice = ""

    var shareURL: URL? {
        shareManager.makeShareURL(
            senderName: senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Aurenda User" : senderName.trimmingCharacters(in: .whitespacesAndNewlines),
            permission: permission,
            events: events
        )
    }

    var sortedEvents: [CalendarEvent] {
        events.sorted { $0.startDate < $1.startDate }
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
                    if permission == .edit {
                        Text("Receiver can modify event details.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                Section("Invite Preview") {
                    ForEach(sortedEvents.prefix(4)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .auraFont(size: 14, weight: .semibold)
                            Text(inviteDateLabel(event))
                                .auraFont(size: 12, weight: .medium)
                                .foregroundColor(.secondary)
                        }
                    }
                    if sortedEvents.count > 4 {
                        Text("+\(sortedEvents.count - 4) more events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section {
                    if let u = shareURL {
                        ShareLink(item: u) {
                            Label("Share via AirDrop / Messages", systemImage: "square.and.arrow.up")
                                .auraFont(size: 16, weight: .semibold)
                        }
                        Button {
                            UIPasteboard.general.url = u
                            store.logShareInvite(events: sortedEvents, permission: permission, via: "Copied Link")
                            shareNotice = "Invite link copied."
                        } label: {
                            Label("Copy Invite Link", systemImage: "link")
                        }
                    }
                    if !shareNotice.isEmpty {
                        Text(shareNotice)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    senderName = storedDisplayName.isEmpty ? "Aurenda User" : storedDisplayName
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
                shareNotice = ""
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func inviteDateLabel(_ event: CalendarEvent) -> String {
        if event.isAllDay {
            return "\(event.startDate.formatted(date: .abbreviated, time: .omitted)) · All day"
        }
        return event.startDate.formatted(date: .abbreviated, time: .shortened)
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
                    .auraFont(size: 56, weight: .light)
                    .foregroundStyle(LinearGradient(
                        colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            VStack(spacing: 10) {
                Text("No Events Yet")
                    .auraFont(size: 24, weight: .bold, design: .rounded)
                Text("Tap + to schedule your first event")
                    .auraFont(size: 15)
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
                    .auraFont(size: 19, weight: .bold, design: .rounded)
                    .foregroundColor(isToday ? .white : .primary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(weekday)
                    .auraFont(size: 15, weight: .bold)
                    .foregroundColor(isToday ? AuraThemePalette.current.accentStart : .primary)
                Text(monthYear)
                    .auraFont(size: 11, weight: .medium)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

struct AgendaScrollOffsetKey: PreferenceKey {
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
                    .auraFont(size: 11, weight: .bold, design: .rounded)
                    .foregroundColor(catColor)
                if !event.isAllDay {
                    Text(endStr)
                        .auraFont(size: 10)
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
                    .auraFont(size: 15, weight: .bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let c = cat {
                        HStack(spacing: 4) {
                            Image(systemName: c.icon)
                                .auraFont(size: 10, weight: .semibold)
                            Text(c.name)
                                .auraFont(size: 11, weight: .semibold)
                        }
                        .foregroundColor(catColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(catColor.opacity(0.18), in: Capsule())
                    }
                    if event.hasAlarm {
                        Image(systemName: "bell.fill")
                            .auraFont(size: 10)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    if event.recurrence != .none {
                        Image(systemName: "repeat")
                            .auraFont(size: 10)
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
