// ============================================================
//  AuraShareImport -- Share Extension
//  Lets a user share a calendar invite (.ics) or plain text
//  (e.g. a WhatsApp message, a casual email) into Aurenda.
//  Runs in its own process/sandbox, so it can't call into the
//  main app's EventStore directly -- it writes parsed drafts to
//  the shared App Group container instead, and the main app
//  picks them up next time it's opened (see SharedImportInbox
//  and the import-queue handling in AuraAppShellView).
//
//  The draft type + parsers below are intentionally duplicated
//  from the main target rather than shared via a framework --
//  this mirrors how AuraNotificationContent/AuraWidget already
//  re-decode shared state independently rather than linking
//  against the main app's single source file.
// ============================================================

import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared draft type (must match AuraImportedEventDraft in AuraApp.swift)

struct AuraImportedEventDraft: Codable, Identifiable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var location: String = ""
    var startDate: Date
    var endDate: Date
    var sourceLabel: String = "Import"
}

enum SharedImportInbox {
    private static let key = "aura.pendingImportedEvents"
    private static var shared: UserDefaults { UserDefaults(suiteName: "group.com.personal.aura") ?? .standard }

    static func append(_ drafts: [AuraImportedEventDraft]) {
        var existing: [AuraImportedEventDraft] = []
        if let data = shared.data(forKey: key) {
            existing = (try? JSONDecoder().decode([AuraImportedEventDraft].self, from: data)) ?? []
        }
        existing.append(contentsOf: drafts)
        if let data = try? JSONEncoder().encode(existing) {
            shared.set(data, forKey: key)
        }
    }
}

// MARK: - ICS parser (RFC 5545 subset: enough for real-world meeting invites)

enum ICSParser {
    static func parseEvents(from text: String) -> [AuraImportedEventDraft] {
        let unfolded = unfold(text)
        let lines = unfolded.components(separatedBy: .newlines)
        var drafts: [AuraImportedEventDraft] = []
        var current: [String: String] = [:]
        var inEvent = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line == "BEGIN:VEVENT" { inEvent = true; current = [:]; continue }
            if line == "END:VEVENT" {
                inEvent = false
                if let draft = makeDraft(from: current) { drafts.append(draft) }
                continue
            }
            guard inEvent, let colonIdx = line.firstIndex(of: ":") else { continue }
            let keyAndParams = String(line[line.startIndex..<colonIdx])
            let value = String(line[line.index(after: colonIdx)...])
            let key = keyAndParams.split(separator: ";").first.map(String.init) ?? keyAndParams
            if key == "DTSTART" || key == "DTEND" {
                current[key] = keyAndParams + ":" + value
            } else {
                current[key] = unescape(value)
            }
        }
        return drafts
    }

    private static func unfold(_ text: String) -> String {
        var result = ""
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                result += line.dropFirst()
            } else {
                if !result.isEmpty { result += "\n" }
                result += line
            }
        }
        return result
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n")
         .replacingOccurrences(of: "\\N", with: "\n")
         .replacingOccurrences(of: "\\,", with: ",")
         .replacingOccurrences(of: "\\;", with: ";")
         .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func makeDraft(from fields: [String: String]) -> AuraImportedEventDraft? {
        guard let dtStartRaw = fields["DTSTART"], let start = parseDate(dtStartRaw) else { return nil }
        let end = fields["DTEND"].flatMap(parseDate) ?? start.addingTimeInterval(3600)
        let title = fields["SUMMARY"] ?? "Imported Event"
        let location = fields["LOCATION"] ?? ""
        let notes = fields["DESCRIPTION"] ?? ""
        return AuraImportedEventDraft(title: title, notes: notes, location: location, startDate: start, endDate: end, sourceLabel: "Calendar Invite")
    }

    private static func parseDate(_ raw: String) -> Date? {
        guard let colonIdx = raw.firstIndex(of: ":") else { return nil }
        let paramsPart = String(raw[raw.startIndex..<colonIdx])
        let valuePart = String(raw[raw.index(after: colonIdx)...])
        let params = paramsPart.split(separator: ";").dropFirst()
        var tzid: String? = nil
        var isDateOnly = false
        for p in params {
            if p.hasPrefix("TZID=") { tzid = String(p.dropFirst(5)) }
            if p == "VALUE=DATE" { isDateOnly = true }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if isDateOnly {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = TimeZone.current
            return formatter.date(from: valuePart)
        }
        if valuePart.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.date(from: valuePart)
        }
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = tzid.flatMap(TimeZone.init(identifier:)) ?? TimeZone.current
        return formatter.date(from: valuePart)
    }
}

// MARK: - Free-text parser (WhatsApp messages, casual emails with no .ics attached)

enum SharedTextEventParser {
    static func parse(_ text: String, sourceLabel: String) -> AuraImportedEventDraft? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range), let date = match.date else { return nil }
        let duration = match.duration > 0 ? match.duration : 3600
        let firstLine = text.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Imported Event"
        let title = String(firstLine.trimmingCharacters(in: .whitespaces).prefix(80))
        return AuraImportedEventDraft(
            title: title.isEmpty ? "Imported Event" : title,
            notes: text,
            location: "",
            startDate: date,
            endDate: date.addingTimeInterval(duration),
            sourceLabel: sourceLabel
        )
    }
}

// MARK: - View Controller

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let hosting = UIHostingController(rootView: ShareImportView(
            onFinish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            onCancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: NSError(domain: "AuraShareImport", code: 0)) },
            extensionItems: extensionContext?.inputItems as? [NSExtensionItem] ?? []
        ))
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hosting.view.backgroundColor = .clear
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }
}

// MARK: - SwiftUI content

struct ShareImportView: View {
    let onFinish: () -> Void
    let onCancel: () -> Void
    let extensionItems: [NSExtensionItem]

    @State private var drafts: [AuraImportedEventDraft] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Reading…").foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if drafts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text(errorMessage ?? "Couldn't find a date or event in this.")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(drafts) { d in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.title).font(.system(size: 16, weight: .semibold))
                            Text(d.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            if !d.location.isEmpty {
                                Text(d.location).font(.system(size: 13)).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Add to Aurenda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        SharedImportInbox.append(drafts)
                        onFinish()
                    }
                    .disabled(drafts.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let item = extensionItems.first, let attachments = item.attachments, !attachments.isEmpty else {
            isLoading = false
            return
        }

        let icsType = "com.apple.ical.ics"
        let group = DispatchGroup()
        var collected: [AuraImportedEventDraft] = []

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(icsType) {
                group.enter()
                provider.loadItem(forTypeIdentifier: icsType, options: nil) { data, _ in
                    defer { group.leave() }
                    let text = Self.extractText(data)
                    if let text {
                        collected.append(contentsOf: ICSParser.parseEvents(from: text))
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                    defer { group.leave() }
                    guard let text = Self.extractText(data) else { return }
                    if text.contains("BEGIN:VEVENT") {
                        collected.append(contentsOf: ICSParser.parseEvents(from: text))
                    } else if let draft = SharedTextEventParser.parse(text, sourceLabel: "Shared Text") {
                        collected.append(draft)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            self.drafts = collected
            self.isLoading = false
        }
    }

    private static func extractText(_ data: NSSecureCoding?) -> String? {
        if let text = data as? String { return text }
        if let url = data as? URL, let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        if let raw = data as? Data, let text = String(data: raw, encoding: .utf8) { return text }
        return nil
    }
}
