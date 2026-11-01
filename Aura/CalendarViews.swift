import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

// MARK: - Calendar View

enum CalendarScope: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
}

enum CalendarSourceFilter: String, CaseIterable {
    case thisGroup = "This Group"
    case personalOnly = "Personal Only"
    case allGroups = "All Groups"

    var icon: String {
        switch self {
        case .thisGroup: return "person.3.fill"
        case .personalOnly: return "person.fill"
        case .allGroups: return "square.stack.3d.up.fill"
        }
    }
}

struct CalendarView: View {
    @State private var eventPendingDelete: CalendarEvent? = nil
    @EnvironmentObject var store: EventStore
    @Binding var showCreate: Bool
    @State private var selectedDate = Date()
    @State private var month = Date()
    @State private var selected: CalendarEvent?
    @State private var editingEvent: CalendarEvent?
    @State private var scope: CalendarScope = .month
    @State private var sourceFilter: CalendarSourceFilter = .thisGroup

    var cal: Calendar { .current }
    var weekStart: Date {
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        return cal.date(from: comps) ?? selectedDate
    }

    var body: some View {
        NavigationView {
            ZStack {
                AuraAtmosphericBackground()
                VStack(spacing: 0) {
                    if store.hasServerGroups {
                        HStack {
                            Menu {
                                ForEach(availableFilters, id: \.self) { f in
                                    Button {
                                        sourceFilter = f
                                    } label: {
                                        Label(f.rawValue, systemImage: f == sourceFilter ? "checkmark" : f.icon)
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: sourceFilter.icon)
                                    Text(sourceFilter.rawValue)
                                    Image(systemName: "chevron.down")
                                        .auraFont(size: 10, weight: .semibold)
                                }
                                .auraFont(size: 12, weight: .semibold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground).opacity(0.7), in: Capsule())
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }

                    Picker("Scope", selection: $scope) {
                        ForEach(CalendarScope.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .opacity(sourceFilter == .allGroups ? 0.4 : 1)
                    .disabled(sourceFilter == .allGroups)

                    Group {
                        if sourceFilter == .allGroups {
                            MergedGroupsCalendarList(onSelect: { event in selected = event })
                        } else {
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
                }
            }
            .navigationTitle("Calendar")
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
        }
        .sheet(item: $selected) { e in
            EventDetailView(event: e).environmentObject(store)
        }
        .sheet(item: $editingEvent) { event in
            CreateEventView(
                isPresented: Binding(get: { true }, set: { _ in editingEvent = nil }),
                editing: event
            )
            .environmentObject(store)
        }
        .onChange(of: sourceFilter) { newValue in
            if newValue == .allGroups && store.personalMasterCalendarItems.isEmpty && !store.isLoadingPersonalLayer {
                Task { await store.refreshPersonalLayer() }
            }
        }
    }

    var availableFilters: [CalendarSourceFilter] {
        store.serverGroups.count > 1
            ? CalendarSourceFilter.allCases
            : [.thisGroup, .personalOnly]
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
        MonthGrid(month: month, selected: $selectedDate, personalOnly: sourceFilter == .personalOnly)
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
                        .auraFont(size: 17, weight: .bold)
                    // The heading already says "Today"; give the date instead.
                    if cal.isDateInToday(date) {
                        Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .auraFont(size: 11, weight: .semibold)
                            .foregroundColor(AuraThemePalette.current.accentStart)
                    }
                }
                Spacer()
                let count = filteredEvents(for: date).count
                if count > 0 {
                    Text("\(count) event\(count == 1 ? "" : "s")")
                        .auraFont(size: 12, weight: .semibold)
                        .foregroundColor(AuraThemePalette.current.accentStart)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(AuraThemePalette.current.accentStart.opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            if filteredEvents(for: date).isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "moon.stars")
                            .auraFont(size: 28)
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No events this day")
                            .auraFont(size: 14)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredEvents(for: date)) { e in
                            EventRow(event: e)
                                .padding(.horizontal, 16)
                                .onTapGesture { selected = e }
                                .contextMenu {
                                    Button {
                                        selected = e
                                    } label: {
                                        Label("View Details", systemImage: "eye.fill")
                                    }
                                    Button {
                                        editingEvent = e
                                    } label: {
                                        Label(store.canEdit(e) ? "Edit" : "Suggest Changes", systemImage: "pencil")
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
        let base = sourceFilter == .personalOnly
            ? store.visibleEvents.filter { $0.visibility == .personal }
            : store.visibleEvents
        return base.filter {
            let c = cal.dateComponents([.year, .month], from: $0.startDate)
            return c.year == y && c.month == monthIndex
        }.count
    }

    func filteredEvents(for date: Date) -> [CalendarEvent] {
        let base = store.events(for: date)
        return sourceFilter == .personalOnly ? base.filter { $0.visibility == .personal } : base
    }

    func isCurrentMonth(monthIndex: Int, yearDate: Date) -> Bool {
        let now = Date()
        return cal.component(.year, from: now) == cal.component(.year, from: yearDate)
            && cal.component(.month, from: now) == monthIndex
    }
}

/// Reads from the same cross-group personal aggregate the Personal tab uses
/// (server-computed across every group the user belongs to). Read-only: items
/// from a group other than the currently active one won't resolve to a local
/// `CalendarEvent`, so tapping them just falls back to a status message
/// instead of opening the full detail sheet.
struct MergedGroupsCalendarList: View {
    @EnvironmentObject var store: EventStore
    var onSelect: (CalendarEvent) -> Void
    @State private var statusMessage: String? = nil

    var groupedByDay: [(String, [AuraRemotePersonalAggregateItem])] {
        let calendarItems = store.personalMasterCalendarItems
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"
        let iso = ISO8601DateFormatter()
        let groups = Dictionary(grouping: calendarItems) { item -> String in
            guard let raw = item.payload["startDate"], let d = iso.date(from: raw) else { return "Undated" }
            return df.string(from: d)
        }
        return groups.sorted { $0.key < $1.key }
    }

    var body: some View {
        if store.isLoadingPersonalLayer {
            VStack { Spacer(); ProgressView(); Spacer() }
        } else if store.personalMasterCalendarItems.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "square.stack.3d.up.slash")
                    .auraFont(size: 28)
                    .foregroundColor(.secondary.opacity(0.4))
                Text("Nothing across your groups yet")
                    .auraFont(size: 14)
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let statusMessage {
                        Text(statusMessage)
                            .auraFont(size: 11, weight: .medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                    }
                    ForEach(groupedByDay, id: \.0) { day, items in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(day)
                                .auraFont(size: 13, weight: .bold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                            VStack(spacing: 8) {
                                ForEach(items) { item in
                                    PersonalAggregateRow(item: item, fallbackIcon: "calendar") {
                                        if let event = store.eventFromPayload(item.payload) {
                                            onSelect(event)
                                        } else {
                                            statusMessage = "That event belongs to a different group -- switch to it to open full details."
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
        }
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
                    .auraFont(size: 14, weight: .semibold)
                    .foregroundColor(AuraThemePalette.current.accentStart)
                    .frame(width: 34, height: 34)
                    .background(AuraThemePalette.current.accentStart.opacity(0.12), in: Circle())
            }
            Spacer()
            Text(title)
                .auraFont(size: 18, weight: .bold, design: .rounded)
            Spacer()
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .auraFont(size: 14, weight: .semibold)
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
                            .auraFont(size: 10, weight: .medium)
                            .foregroundColor(selected ? .white.opacity(0.9) : .secondary)
                        Text("\(cal.component(.day, from: d))")
                            .auraFont(size: 14, weight: .bold)
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
                    .auraFont(size: 14, weight: .bold)
                    .foregroundColor(isCurrentMonth ? AuraThemePalette.current.accentStart : .primary)
                Text("\(eventCount)")
                    .auraFont(size: 18, weight: .bold, design: .rounded)
                    .foregroundColor(.primary)
                Text(eventCount == 1 ? "event" : "events")
                    .auraFont(size: 10, weight: .medium)
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
                .auraFont(size: 20, weight: .bold, design: .rounded)
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
                .accessibilityLabel(dir < 0 ? "Previous" : "Next")
                .auraFont(size: 17, weight: .semibold)
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
                    .auraFont(size: 12, weight: .medium)
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
    var personalOnly: Bool = false
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
                    DayCell(date: date, selected: $selected, personalOnly: personalOnly)
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
    var personalOnly: Bool = false
    @EnvironmentObject var store: EventStore

    var isSel:     Bool  { Calendar.current.isDate(date, inSameDayAs: selected) }
    var isToday:   Bool  { Calendar.current.isDateInToday(date) }
    var day:       Int   { Calendar.current.component(.day, from: date) }
    var evts:      [CalendarEvent] {
        let base = store.events(for: date)
        return personalOnly ? base.filter { $0.visibility == .personal } : base
    }
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
