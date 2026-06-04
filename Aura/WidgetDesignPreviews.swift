// ============================================================
//  WidgetDesignPreviews.swift
//  Aura — Widget UI Options (Preview Only — delete after choosing)
//  Open this file in Xcode and show the Canvas (⌥⌘↩) to preview
// ============================================================

import SwiftUI

// MARK: - Shared sample data

let sampleColor   = Color(hex: "6366F1")
let sampleColor2  = Color(hex: "EC4899")
let sampleColor3  = Color(hex: "14B8A6")

struct SampleEvent {
    let title: String
    let category: String
    let icon: String
    let color: Color
    let time: String
    let isAllDay: Bool
}

let events: [SampleEvent] = [
    .init(title: "Doctor · Mama",    category: "Health",   icon: "heart.fill",      color: Color(hex: "FF6B9D"), time: "9:00 AM",  isAllDay: false),
    .init(title: "Meeting · Work",   category: "Work",     icon: "person.3.fill",   color: Color(hex: "8B5CF6"), time: "2:00 PM",  isAllDay: false),
    .init(title: "Choir · Church",   category: "Choir",    icon: "music.note",      color: Color(hex: "7C3AED"), time: "7:00 PM",  isAllDay: false),
    .init(title: "Job Interview",    category: "Career",   icon: "briefcase.fill",  color: Color(hex: "14B8A6"), time: "All Day",   isAllDay: true),
]

// ============================================================
// MARK: - OPTION A  "Next Up"  (Dark Gradient, Minimal)
//  Best for: Small & Medium widgets
//  Vibe: Premium, sleek, focus on ONE event
// ============================================================

struct WidgetOptionA_Small: View {
    let event = events[0]
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1E1B4B"), Color(hex: "312E81")],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(alignment: .leading, spacing: 6) {
                // Top pill
                HStack(spacing: 4) {
                    Image(systemName: event.icon)
                        .font(.system(size: 9, weight: .semibold))
                    Text(event.category.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.white.opacity(0.15), in: Capsule())

                Spacer()

                Text("NEXT UP")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "A5B4FC"))

                Text(event.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "clock.fill").font(.system(size: 10))
                    Text(event.time).font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.65))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct WidgetOptionA_Medium: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1E1B4B"), Color(hex: "4C1D95")],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            HStack(spacing: 0) {
                // Left — main event
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEXT UP")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "A5B4FC"))

                    Text(events[0].title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill").font(.system(size: 11))
                        Text(events[0].time).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.65))

                    Spacer()

                    // Category badge
                    HStack(spacing: 5) {
                        Image(systemName: events[0].icon).font(.system(size: 10))
                        Text(events[0].category).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.15), in: Capsule())
                }
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .topLeading)

                Spacer()

                // Right — upcoming count
                VStack(spacing: 6) {
                    Spacer()
                    Text("Today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(events.count)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("events")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
                .frame(width: 80)
                .background(.white.opacity(0.07))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// ============================================================
// MARK: - OPTION B  "Today's Agenda"  (Light Card, List)
//  Best for: Medium & Large widgets
//  Vibe: Clean, functional, iOS-native feel
// ============================================================

struct WidgetOptionB_Medium: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TODAY")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(sampleColor)
                        Text("Thursday, 8 May")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Spacer()
                    Text("\(events.count) events")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)

                Divider().padding(.horizontal, 14)

                // Event list
                ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, e in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(e.color)
                            .frame(width: 3, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text(e.time)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: e.icon)
                            .font(.system(size: 12))
                            .foregroundColor(e.color.opacity(0.8))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 5)
                }

                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct WidgetOptionB_Large: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TODAY")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(sampleColor)
                        Text("Thursday, 8 May 2026")
                            .font(.system(size: 15, weight: .bold))
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(sampleColor.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Text("8")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(sampleColor)
                    }
                }
                .padding(16)

                Divider().padding(.horizontal, 16)

                ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(e.color)
                            .frame(width: 4, height: 46)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.title)
                                .font(.system(size: 14, weight: .semibold))
                            HStack(spacing: 4) {
                                Image(systemName: e.icon).font(.system(size: 10))
                                Text(e.time).font(.system(size: 11))
                            }
                            .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)

                    if events.last?.title != e.title {
                        Divider().padding(.leading, 32)
                    }
                }

                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// ============================================================
// MARK: - OPTION C  "Calendar + Dots"  (Mini Grid)
//  Best for: Small & Medium widgets
//  Vibe: Familiar calendar look, at-a-glance month overview
// ============================================================

struct WidgetOptionC_Small: View {
    private let days = ["S","M","T","W","T","F","S"]
    private let eventDays: Set<Int> = [2, 8, 12, 15, 22, 28]
    private let today = 8

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)

            VStack(spacing: 4) {
                // Month label
                Text("MAY 2026")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(sampleColor)

                // Weekday row
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in
                        Text(d)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Days grid (simplified May 2026 — starts Thursday = index 4)
                let allDays: [Int?] = [nil, nil, nil, nil, 1, 2, 3,
                                        4, 5, 6, 7, 8, 9, 10,
                                       11,12,13,14,15,16,17,
                                       18,19,20,21,22,23,24,
                                       25,26,27,28,29,30,31]
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                    ForEach(Array(allDays.prefix(28).enumerated()), id: \.offset) { _, d in
                        if let d = d {
                            ZStack {
                                if d == today {
                                    Circle().fill(sampleColor).frame(width: 18, height: 18)
                                }
                                Text("\(d)")
                                    .font(.system(size: 8, weight: d == today ? .bold : .regular))
                                    .foregroundColor(d == today ? .white : .primary)
                            }
                            .frame(height: 18)
                            .overlay(alignment: .bottom) {
                                if eventDays.contains(d) && d != today {
                                    Circle().fill(sampleColor).frame(width: 3, height: 3)
                                        .offset(y: 1)
                                }
                            }
                        } else {
                            Color.clear.frame(height: 18)
                        }
                    }
                }

                Divider()

                // Next event
                HStack(spacing: 4) {
                    Circle().fill(sampleColor2).frame(width: 6, height: 6)
                    Text("Choir · Church  7 PM")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct WidgetOptionC_Medium: View {
    private let days = ["S","M","T","W","T","F","S"]
    private let eventDays: Set<Int> = [2, 8, 12, 15, 22, 28]
    private let today = 8

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)

            HStack(alignment: .top, spacing: 0) {
                // Left: Mini calendar
                VStack(spacing: 4) {
                    Text("MAY 2026")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(sampleColor)

                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { d in
                            Text(d)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    let allDays: [Int?] = [nil, nil, nil, nil, 1, 2, 3,
                                            4, 5, 6, 7, 8, 9, 10,
                                           11,12,13,14,15,16,17,
                                           18,19,20,21,22,23,24,
                                           25,26,27,28,29,30,31]
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                        ForEach(Array(allDays.prefix(28).enumerated()), id: \.offset) { _, d in
                            if let d = d {
                                ZStack {
                                    if d == today {
                                        Circle().fill(sampleColor).frame(width: 20, height: 20)
                                    }
                                    Text("\(d)")
                                        .font(.system(size: 9, weight: d == today ? .bold : .regular))
                                        .foregroundColor(d == today ? .white : .primary)
                                }
                                .frame(height: 20)
                                .overlay(alignment: .bottom) {
                                    if eventDays.contains(d) && d != today {
                                        Circle().fill(sampleColor).frame(width: 3, height: 3).offset(y: 1)
                                    }
                                }
                            } else {
                                Color.clear.frame(height: 20)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxHeight: .infinity, alignment: .top)

                Divider()

                // Right: Today's events
                VStack(alignment: .leading, spacing: 6) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(sampleColor)
                    ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, e in
                        HStack(spacing: 6) {
                            Circle().fill(e.color).frame(width: 7, height: 7)
                            Text(e.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// ============================================================
// MARK: - OPTION D  "Countdown"  (Bold number, eye-catching)
//  Best for: Small widget
//  Vibe: High impact, great for upcoming important events
// ============================================================

struct WidgetOptionD_Small: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
                startPoint: .top, endPoint: .bottom)

            VStack(spacing: 2) {
                Spacer()

                Text("3")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(hex: "6366F1"), Color(hex: "A78BFA")],
                                       startPoint: .top, endPoint: .bottom))

                Text("DAYS TO")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(2)

                Spacer()

                Divider().background(.white.opacity(0.1))

                HStack(spacing: 5) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "14B8A6"))
                    Text("Job Interview")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct WidgetOptionD_Medium: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            HStack(spacing: 0) {
                // Countdown
                VStack(spacing: 2) {
                    Text("3")
                        .font(.system(size: 60, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(hex: "6366F1"), Color(hex: "A78BFA")],
                                           startPoint: .top, endPoint: .bottom))
                    Text("DAYS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(2)
                }
                .frame(maxHeight: .infinity)
                .padding(.leading, 20)

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 16)

                // Right side
                VStack(alignment: .leading, spacing: 8) {
                    Text("UPCOMING")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(2)

                    HStack(spacing: 6) {
                        Image(systemName: "briefcase.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "14B8A6"))
                        Text("Job Interview")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("Tuesday, 11 May")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))

                    Spacer()

                    Text("Also today: 3 events")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.vertical, 16)
                .padding(.trailing, 16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// ============================================================
// MARK: - Previews  (⌥⌘↩ in Xcode to open Canvas)
// ============================================================

#Preview("Option A — Next Up (Small, Dark)") {
    WidgetOptionA_Small()
        .frame(width: 158, height: 158)
        .padding()
}

#Preview("Option A — Next Up (Medium, Dark)") {
    WidgetOptionA_Medium()
        .frame(width: 338, height: 158)
        .padding()
}

#Preview("Option B — Today's Agenda (Medium, Light)") {
    WidgetOptionB_Medium()
        .frame(width: 338, height: 158)
        .padding()
}

#Preview("Option B — Today's Agenda (Large, Light)") {
    WidgetOptionB_Large()
        .frame(width: 338, height: 354)
        .padding()
}

#Preview("Option C — Calendar + Dots (Small)") {
    WidgetOptionC_Small()
        .frame(width: 158, height: 158)
        .padding()
}

#Preview("Option C — Calendar + Dots (Medium)") {
    WidgetOptionC_Medium()
        .frame(width: 338, height: 158)
        .padding()
}

#Preview("Option D — Countdown (Small, Dark)") {
    WidgetOptionD_Small()
        .frame(width: 158, height: 158)
        .padding()
}

#Preview("Option D — Countdown (Medium, Dark)") {
    WidgetOptionD_Medium()
        .frame(width: 338, height: 158)
        .padding()
}
