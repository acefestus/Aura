// ============================================================
//  AuraWidget — WidgetKit Extension
//  Merged A+D design: countdown number + next-up event
//  Reads events & gradient theme from shared App Group
//  App Group: group.com.personal.aura
// ============================================================

import WidgetKit
import SwiftUI

// MARK: - Shared Models (duplicated for widget target isolation)

struct WEvent: Codable {
    var id:         String
    var title:      String
    var startDate:  Date
    var endDate:    Date
    var isAllDay:   Bool
    var categoryId: String
    var recurrence: String
}

struct WCategory: Codable {
    var id:       String
    var name:     String
    var colorHex: String
    var icon:     String
}

struct WGradientTheme: Codable {
    var c1, c2: String   // background hex
    var n1, n2: String   // number hex
    var name:   String
}

// MARK: - App Group Key

private let appGroup = "group.com.personal.aura"

// MARK: - Data Loader

struct WidgetData {
    var countdown:    WEvent?         // soonest future event with a gap >0 days
    var nextUp:       WEvent?         // next upcoming event today or nearest
    var countCategory: WCategory?
    var nextCategory:  WCategory?
    var daysToCountdown: Int
    var todayCount:   Int
    var upcomingEvents: [WEvent]      // next 3 after nextUp
    var upcomingCats:   [WCategory?]
    var theme:         WGradientTheme
    var activeGroupName: String?      // which V2 group workspace this data belongs to, if any
}

func loadWidgetData() -> WidgetData {
    let defaults = UserDefaults(suiteName: appGroup) ?? .standard

    // ── Events ──────────────────────────────────────────────
    var events: [WEvent] = []
    if let d = defaults.data(forKey: "aura.events"),
       let v = try? JSONDecoder().decode([WEvent].self, from: d) {
        events = v
    }

    // ── Categories ───────────────────────────────────────────
    var cats: [WCategory] = []
    if let d = defaults.data(forKey: "aura.categories"),
       let v = try? JSONDecoder().decode([WCategory].self, from: d) {
        cats = v
    }
    func cat(_ id: String) -> WCategory? { cats.first { $0.id == id } }

    // ── Theme ────────────────────────────────────────────────
    var theme = WGradientTheme(c1:"1E1B4B", c2:"4C1D95", n1:"6366F1", n2:"A78BFA", name:"Indigo Night")
    if let s = defaults.string(forKey: "widgetThemeJSON"),
       let d = s.data(using: .utf8),
       let t = try? JSONDecoder().decode(WGradientTheme.self, from: d) {
        theme = t
    }

    let now     = Date()
    let cal     = Calendar.current
    let today   = cal.startOfDay(for: now)
    let future  = events.filter { $0.startDate >= now }.sorted { $0.startDate < $1.startDate }

    // next-up: nearest event >= now
    let nextUp  = future.first
    let nextCat = nextUp.flatMap { cat($0.categoryId) }

    // countdown target: first event ≥1 day away
    let countdown     = future.first { cal.startOfDay(for: $0.startDate) > today }
    let countdownCat  = countdown.flatMap { cat($0.categoryId) }
    let daysTo: Int   = countdown.map {
        max(0, cal.dateComponents([.day], from: today,
            to: cal.startOfDay(for: $0.startDate)).day ?? 0)
    } ?? 0

    // today count
    let todayCount = events.filter { cal.isDate($0.startDate, inSameDayAs: now) }.count

    // upcoming list (next 3 after nextUp)
    let upcoming = Array(future.dropFirst().prefix(3))
    let upcomingCats: [WCategory?] = upcoming.map { cat($0.categoryId) }

    // ── Active group (V2) ───────────────────────────────────
    let activeGroupName = defaults.string(forKey: "aura.activeGroupName").flatMap { $0.isEmpty ? nil : $0 }

    return WidgetData(
        countdown:       countdown,
        nextUp:          nextUp,
        countCategory:   countdownCat,
        nextCategory:    nextCat,
        daysToCountdown: daysTo,
        todayCount:      todayCount,
        upcomingEvents:  upcoming,
        upcomingCats:    upcomingCats,
        theme:           theme,
        activeGroupName: activeGroupName
    )
}

// MARK: - Timeline Entry

struct AuraEntry: TimelineEntry {
    let date:   Date
    let data:   WidgetData
}

// MARK: - Provider

struct AuraProvider: TimelineProvider {
    func placeholder(in context: Context) -> AuraEntry {
        AuraEntry(date: Date(), data: placeholderData())
    }
    func getSnapshot(in context: Context, completion: @escaping (AuraEntry) -> Void) {
        completion(AuraEntry(date: Date(), data: context.isPreview ? placeholderData() : loadWidgetData()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AuraEntry>) -> Void) {
        let entry    = AuraEntry(date: Date(), data: loadWidgetData())
        let nextDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextDate)))
    }

    func placeholderData() -> WidgetData {
        let start = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let today = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let e1 = WEvent(id:"1", title:"Job Interview",   startDate: start, endDate: start, isAllDay: true,  categoryId:"c1", recurrence:"none")
        let e2 = WEvent(id:"2", title:"Doctor · Mama",   startDate: today, endDate: today, isAllDay: false, categoryId:"c2", recurrence:"none")
        let e3 = WEvent(id:"3", title:"Meeting · Work",  startDate: today, endDate: today, isAllDay: false, categoryId:"c3", recurrence:"none")
        let c1 = WCategory(id:"c1", name:"Job Interview", colorHex:"14B8A6", icon:"briefcase.fill")
        let c2 = WCategory(id:"c2", name:"Health",        colorHex:"FF6B9D", icon:"heart.fill")
        let c3 = WCategory(id:"c3", name:"Work",          colorHex:"8B5CF6", icon:"person.3.fill")
        return WidgetData(
            countdown:       e1,
            nextUp:          e2,
            countCategory:   c1,
            nextCategory:    c2,
            daysToCountdown: 3,
            todayCount:      4,
            upcomingEvents:  [e3],
            upcomingCats:    [c3],
            theme:           WGradientTheme(c1:"1E1B4B",c2:"4C1D95",n1:"6366F1",n2:"A78BFA",name:"Indigo Night"),
            activeGroupName: "Family"
        )
    }
}

// MARK: - Colour Helpers

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Shared Sub-views

private struct GroupBadge: View {
    let name: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 8, weight: .bold))
            Text(name)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.55))
    }
}

private struct CategoryPill: View {
    let name: String
    let icon: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(name)
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.white.opacity(0.15), in: Capsule())
    }
}

private struct CountdownBlock: View {
    let days:   Int
    let label:  String
    let n1, n2: Color
    let size:   CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DAYS TO")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1.5)
            Text("\(days)")
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(
                    colors: [n1, n2],
                    startPoint: .top, endPoint: .bottom))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.3))
                .tracking(1)
                .lineLimit(1)
        }
    }
}

private struct NextUpBlock: View {
    let eyebrow:  String
    let title:    String
    let timeStr:  String
    let titleSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1.5)
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Label(timeStr, systemImage: "clock")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.45))
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: AuraEntry

    private var d: WidgetData { entry.data }
    private var bg:   (Color, Color) { (Color(hex: d.theme.c1), Color(hex: d.theme.c2)) }
    private var numG: (Color, Color) { (Color(hex: d.theme.n1), Color(hex: d.theme.n2)) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [bg.0, bg.1],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let groupName = d.activeGroupName {
                GroupBadge(name: groupName)
                    .padding(14)
            }
            VStack(alignment: .leading, spacing: 0) {
                // category pill
                if let cat = d.nextCategory ?? d.countCategory {
                    CategoryPill(name: cat.name, icon: cat.icon)
                }
                Spacer()
                // countdown number
                if let _ = d.countdown {
                    HStack(alignment: .bottom, spacing: 8) {
                        CountdownBlock(
                            days:  d.daysToCountdown,
                            label: d.countdown?.title ?? "",
                            n1:    numG.0, n2: numG.1,
                            size:  48)
                    }
                }
                Divider().background(.white.opacity(0.15)).padding(.vertical, 6)
                // next up
                if let e = d.nextUp {
                    NextUpBlock(
                        eyebrow:   "NEXT UP",
                        title:     e.title,
                        timeStr:   formatTime(e),
                        titleSize: 13)
                } else {
                    Text("No events")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: AuraEntry

    private var d: WidgetData { entry.data }
    private var bg:   (Color, Color) { (Color(hex: d.theme.c1), Color(hex: d.theme.c2)) }
    private var numG: (Color, Color) { (Color(hex: d.theme.n1), Color(hex: d.theme.n2)) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [bg.0, bg.1],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let groupName = d.activeGroupName {
                GroupBadge(name: groupName)
                    .padding(14)
            }
            HStack(spacing: 0) {
                // left: countdown
                VStack(alignment: .center, spacing: 4) {
                    Spacer()
                    CountdownBlock(
                        days:  d.daysToCountdown,
                        label: d.countdown?.title ?? "—",
                        n1:    numG.0, n2: numG.1,
                        size:  52)
                    Spacer()
                }
                .frame(width: 110)
                .padding(.leading, 14)

                // divider
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 16)

                // right: category pill + next up + count
                VStack(alignment: .leading, spacing: 0) {
                    if let cat = d.nextCategory {
                        CategoryPill(name: cat.name, icon: cat.icon)
                    }
                    Spacer(minLength: 6)
                    if let e = d.nextUp {
                        NextUpBlock(
                            eyebrow:   "NEXT UP",
                            title:     e.title,
                            timeStr:   formatTime(e),
                            titleSize: 15)
                    }
                    Spacer(minLength: 6)
                    Text("● ● ●  \(d.todayCount) event\(d.todayCount == 1 ? "" : "s") today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
    }
}

// MARK: - Large Widget

struct LargeWidgetView: View {
    let entry: AuraEntry

    private var d: WidgetData { entry.data }
    private var bg:   (Color, Color) { (Color(hex: d.theme.c1), Color(hex: d.theme.c2)) }
    private var numG: (Color, Color) { (Color(hex: d.theme.n1), Color(hex: d.theme.n2)) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [bg.0, bg.1],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                // top hero
                HStack(alignment: .top, spacing: 16) {
                    CountdownBlock(
                        days:  d.daysToCountdown,
                        label: d.countdown?.title ?? "—",
                        n1:    numG.0, n2: numG.1,
                        size:  56)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        if let groupName = d.activeGroupName {
                            GroupBadge(name: groupName)
                        }
                        if let cat = d.nextCategory {
                            CategoryPill(name: cat.name, icon: cat.icon)
                        }
                        if let e = d.nextUp {
                            Text(e.title)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                            Label(formatTime(e), systemImage: "clock")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        Text("\(d.todayCount) events today")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // divider
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                // upcoming list
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(d.upcomingEvents.enumerated()), id: \.offset) { i, e in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: d.upcomingCats[safe: i]??.colorHex ?? "6366F1"))
                                .frame(width: 3, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Label(formatTime(e), systemImage: e.isAllDay ? "calendar" : "clock")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        if i < d.upcomingEvents.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 29)
                        }
                    }
                }
                .padding(.top, 4)
                Spacer()
            }
        }
    }
}

// MARK: - Time Formatter

private func formatTime(_ e: WEvent) -> String {
    if e.isAllDay {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: e.startDate)
    }
    let f = DateFormatter()
    f.timeStyle = .short
    return f.string(from: e.startDate)
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Widget Bundle

@main
struct AuraWidgetBundle: WidgetBundle {
    var body: some Widget {
        AuraWidgetExtension()
    }
}

struct AuraWidgetExtension: Widget {
    let kind = "AuraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AuraProvider()) { entry in
            AuraWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Aura")
        .description("Countdown + upcoming events with your custom gradient.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct AuraWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: AuraEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        case .systemLarge:  LargeWidgetView(entry: entry)
        default:            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Previews

#if swift(>=5.9)
@available(iOS 17.0, *)
private struct AuraWidgetPreviews: PreviewProvider {
    static var previews: some View {
        let data = AuraProvider().previewData()
        let entry = AuraEntry(date: .now, data: data)
        Group {
            SmallWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            MediumWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            LargeWidgetView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif

extension AuraProvider {
    func previewData() -> WidgetData { placeholderData() }
}
