import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

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
                        if !store.isCreator(event.createdByUserId, ownerName: event.ownerName) {
                            InfoCard(icon: "person.crop.circle", label: "Created By",
                                     value: store.creatorName(ownerName: event.ownerName)
                                        + (store.creatorLeft(event.createdByUserId, ownerName: event.ownerName) ? " (left the group)" : ""))
                        }
                        if store.pendingProposal(for: event.id) != nil {
                            InfoCard(icon: "clock.arrow.circlepath", label: "Your Suggested Change",
                                     value: "Waiting for \(store.deciderName(createdByUserId: event.createdByUserId, ownerName: event.ownerName)) to approve",
                                     tint: AuraThemePalette.current.accentStart)
                        }
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
                                if store.canEdit(event) {
                                    Label("Edit", systemImage: "pencil")
                                } else {
                                    Label("Suggest Changes", systemImage: "square.and.pencil")
                                }
                            }
                            if store.canDelete(event) {
                                Button(role: .destructive) { confirmDelete = true } label: {
                                    Label("Delete", systemImage: "trash")
                                }
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
                    subtitle: "Send this event to another Aurenda user.",
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
            return "Whole Group"
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
    var preset: EventDraftPreset? = nil

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
    @State private var automationMessage = ""

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
            assignedMemberIds: Array(assignedMemberIds),
            createdByUserId: editing?.createdByUserId
        )
    }

    /// Editing someone else's event: saving sends a request to its creator.
    var isSuggesting: Bool {
        editing.map { !store.canEdit($0) } ?? false
    }

    var conflicts: [CalendarEvent] {
        store.conflictingEvents(for: draftEvent, excluding: editing?.id)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AuraAtmosphericBackground()
                Form {
                    formTopSections
                    formBottomSections
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(editing == nil ? "New Event" : (isSuggesting ? "Suggest Changes" : "Edit Event"))
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
                    Button(editing == nil ? "Add" : (isSuggesting ? "Send" : "Update")) { save() }
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                ForEach(store.members) { member in
                    Button {
                        if assignedMemberIds.contains(member.id) {
                            assignedMemberIds.remove(member.id)
                        } else {
                            assignedMemberIds.insert(member.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(member.color).frame(width: 12, height: 12)
                            Text(member.name).foregroundColor(.primary)
                            Spacer()
                            if assignedMemberIds.contains(member.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AuraThemePalette.current.accentStart)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(assignedMemberIds.contains(member.id) ? AuraThemePalette.current.accentStart.opacity(0.12) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Section("Visibility") {
            Picker("Who can see this", selection: $visibility) {
                ForEach(VisibilityScope.allCases, id: \.self) { scope in
                    Label(scope.displayName, systemImage: scope.icon).tag(scope)
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
                .onChange(of: start) { newStart in
                    if end < newStart {
                        end = newStart.addingTimeInterval(3600)
                    }
                }
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
        Section("Smart Scheduling") {
            Button {
                applyNextAvailableSlot()
            } label: {
                Label("Find Next Free Group Slot", systemImage: "sparkles")
            }
            .disabled(assignedMemberIds.isEmpty || allDay)

            if recurrence == .none {
                Button {
                    recurrence = .weekly
                    automationMessage = "Set to weekly recurrence."
                } label: {
                    Label("Suggest Weekly Routine", systemImage: "repeat")
                }
            }

            if assignedMemberIds.isEmpty {
                Text("Assign at least one member to enable collision-aware scheduling.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            if !automationMessage.isEmpty {
                Text(automationMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
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
                Text("These members are already booked during this time. You can still save if this overlap is intentional.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Button {
                    applyNextAvailableSlot()
                } label: {
                    Label("Auto Resolve With Next Available Slot", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(allDay || assignedMemberIds.isEmpty)
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
        if editing == nil {
            if let preset {
                title = preset.title
                notes = preset.notes
                location = preset.location
                start = preset.start
                end = preset.end
                if let presetCategoryId = preset.categoryId,
                   store.category(for: presetCategoryId) != nil {
                    catId = presetCategoryId
                }
                visibility = preset.visibility
                sharedWithNames = Set(preset.sharedWithNames)
                assignedMemberIds = Set(preset.assignedMemberIds)
                hasAlarm = preset.hasAlarm
                alarmMins = preset.alarmMins
                recurrence = preset.recurrence
            } else if let activeMember = store.activeMember {
                assignedMemberIds = [activeMember.id]
            }
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
        if editing == nil {
            store.addEvent(draftEvent)
        } else if store.updateEvent(draftEvent) == .proposed, let editing {
            NotificationCenter.default.post(
                name: .auraInAppBanner,
                object: nil,
                userInfo: ["title": "Change requested", "message": "Sent to \(store.deciderName(createdByUserId: editing.createdByUserId, ownerName: editing.ownerName)) to approve."]
            )
        }
        isPresented = false
    }

    func applyNextAvailableSlot() {
        guard !allDay else {
            automationMessage = "Smart scheduling is disabled for all-day events."
            return
        }
        var candidate = draftEvent
        let duration = max(900, end.timeIntervalSince(start))
        candidate.startDate = start
        candidate.endDate = start.addingTimeInterval(duration)
        candidate.assignedMemberIds = Array(assignedMemberIds)

        guard let suggestedStart = store.nextAvailableStart(for: candidate, excluding: editing?.id) else {
            automationMessage = "No free slot found in the next 72 hours."
            return
        }
        if suggestedStart == start {
            automationMessage = "Current slot is already conflict-free."
            return
        }
        start = suggestedStart
        end = suggestedStart.addingTimeInterval(duration)
        automationMessage = "Moved to \(suggestedStart.formatted(date: .abbreviated, time: .shortened))."
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

struct CategoryPickerRow: View {
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

    @State private var showFileImporter = false
    @State private var hasCustomSound = CustomSoundStore.hasCustomSound
    @State private var customDisplayName = CustomSoundStore.displayName
    @State private var importFailed = false

    var body: some View {
        NavigationView {
            List {
                if showClearOption {
                    Section {
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
                }

                Section("Tones") {
                    ForEach(AppSound.tones, id: \.self) { s in
                        soundRow(s)
                    }
                }

                Section {
                    ForEach(AppSound.melodies, id: \.self) { s in
                        soundRow(s)
                    }
                } header: {
                    Text("Melodies")
                } footer: {
                    Text("Original tunes made for Aurenda -- not copies of any commercial ringtone.")
                }

                Section {
                    if hasCustomSound {
                        soundRow(.custom, subtitle: customDisplayName)
                        Button {
                            AuraHaptics.tap(.light)
                            showFileImporter = true
                        } label: {
                            Label("Replace Custom Sound", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button(role: .destructive) {
                            AuraHaptics.tap(.light)
                            CustomSoundStore.remove()
                            hasCustomSound = false
                            if currentSound == .custom { onSelect(.systemDefault) }
                        } label: {
                            Label("Remove Custom Sound", systemImage: "trash")
                        }
                    } else {
                        Button {
                            AuraHaptics.tap(.light)
                            showFileImporter = true
                        } label: {
                            Label("Import a Sound from Files…", systemImage: "waveform.badge.plus")
                        }
                    }
                } header: {
                    Text("Your Own Sound")
                } footer: {
                    Text("Plays in full when Aurenda is open. When your phone is locked, iOS only allows sounds built into the app, so this falls back to Chime.")
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
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.audio]) { result in
                switch result {
                case .success(let url):
                    if CustomSoundStore.importSound(from: url) {
                        hasCustomSound = true
                        customDisplayName = CustomSoundStore.displayName
                        AuraHaptics.success()
                        onSelect(.custom)
                    } else {
                        importFailed = true
                    }
                case .failure:
                    importFailed = true
                }
            }
            .alert("Couldn't Import Sound", isPresented: $importFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That file couldn't be used as an alert sound. Try a different audio file.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func soundRow(_ s: AppSound, subtitle: String? = nil) -> some View {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(s.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if s != .silent {
                Button {
                    AuraHaptics.tap(.light)
                    s.preview()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
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
        .onTapGesture {
            AuraHaptics.tap(.medium)
            onSelect(s)
            isPresented = false
        }
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
