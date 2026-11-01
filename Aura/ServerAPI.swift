import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

struct AuraRemoteUser: Codable {
    var id: String
    var email: String
    var displayName: String
}

struct AuraRemoteMembership: Codable {
    var userId: String
    var householdId: String
    var role: String
    var joinedAt: String
}

struct AuraRemoteHousehold: Codable {
    var id: String
    var name: String
    var code: String
    var createdBy: String
    var createdAt: String
}

struct AuraRemoteGroup: Codable, Identifiable {
    var id: String
    var name: String
    var type: String
    var code: String
    var createdBy: String
    var createdAt: String
}

struct AuraRemoteGroupMembership: Codable {
    var userId: String
    var groupId: String
    var role: String
    var joinedAt: String
}

struct AuraRemoteGroupRecord: Codable, Identifiable {
    var group: AuraRemoteGroup
    var membership: AuraRemoteGroupMembership

    var id: String { group.id }
}

struct AuraRemoteGroupsResponse: Codable {
    var groups: [AuraRemoteGroupRecord]
}

struct AuraRemoteGroupMemberRecord: Codable, Identifiable {
    var membership: AuraRemoteGroupMembership
    var user: AuraRemoteUser?

    var id: String { membership.userId }
}

struct AuraRemoteGroupMembersResponse: Codable {
    var group: AuraRemoteGroup
    var currentUserId: String
    var members: [AuraRemoteGroupMemberRecord]
}

struct AuraRemoteGroupMembershipEnvelope: Codable {
    var membership: AuraRemoteGroupMembership
}

struct AuraRemoteGroupEnvelope: Codable {
    var group: AuraRemoteGroup
}

struct AuraRemoteGroupPayloadRecord: Codable, Identifiable {
    var id: String
    var groupId: String
    var createdBy: String
    var updatedAt: String
    var payload: [String: String]
}

struct AuraRemotePersonalAggregateItem: Codable, Identifiable {
    var id: String
    var groupId: String
    var createdBy: String
    var updatedAt: String
    var payload: [String: String]
    var group: AuraRemoteGroup?
}

struct AuraRemotePersonalAggregateResponse: Codable {
    var items: [AuraRemotePersonalAggregateItem]
    var total: Int
}

struct AuraRemoteConflictRecord: Codable, Identifiable {
    var leftEventId: String
    var rightEventId: String
    var leftEventTitle: String?
    var rightEventTitle: String?
    var severity: String

    var id: String { "\(leftEventId)-\(rightEventId)" }
}

struct AuraRemoteConflictsResponse: Codable {
    var conflicts: [AuraRemoteConflictRecord]
    var total: Int
}

struct AuraRemoteConflictInterceptResponse: Codable {
    var ok: Bool
    var action: String
    var suggestionStart: String?
    var suggestionEnd: String?
    var resolvedEventId: String?
    var eventTitle: String?
    var groupId: String?
    var beforeStart: String?
    var beforeEnd: String?
    var afterStart: String?
    var afterEnd: String?
    var remainingConflicts: Int?
    var updatedEvent: AuraRemoteGroupPayloadRecord?
}

struct AuraRemoteAuthResponse: Codable {
    var token: String
    var user: AuraRemoteUser
}

struct AuraRemoteMeResponse: Codable {
    var user: AuraRemoteUser
    var membership: AuraRemoteMembership?
    var isAdmin: Bool?
}

struct AuraRemoteCurrentHouseholdResponse: Codable {
    var household: AuraRemoteHousehold?
    var membership: AuraRemoteMembership?
}

struct AuraRemoteSnapshotRecord: Codable {
    var householdId: String
    /// Kept as the server's exact string: it's echoed back as `since` to ask
    /// "anything new?", which the server answers by string equality.
    var updatedAt: String
    var updatedBy: String
    var payload: HouseholdSyncPayload
}

struct AuraRemoteSnapshotEnvelope: Codable {
    var snapshot: AuraRemoteSnapshotRecord?
    /// Set when the request passed `since` and nothing has changed.
    var unchanged: Bool? = nil
    /// The group's current members, sent with every reply.
    var groupMembers: [AuraRemoteMemberRef]? = nil
}

struct AuraRemoteMemberRef: Codable, Equatable {
    var userId: String
    var displayName: String
}

struct AuraRemoteUserEnvelope: Codable {
    var user: AuraRemoteUser
}

struct AuraRemoteOkEnvelope: Codable {
    var ok: Bool
}


struct AuraRemoteAuditEntry: Codable, Identifiable {
    var id: String
    var householdId: String?
    var groupId: String?
    var actorUserId: String
    var action: String
    var targetUserId: String?
    var details: String?
    var createdAt: String
}

struct AuraRemoteAuditResponse: Codable {
    var entries: [AuraRemoteAuditEntry]
}

struct AuraRemoteGroupConflictHistoryEntry: Codable, Identifiable {
    var id: String
    var action: String
    var actorUserId: String
    var createdAt: String
    var details: String
}

struct AuraRemoteGroupConflictHistoryResponse: Codable {
    var groupId: String
    var entries: [AuraRemoteGroupConflictHistoryEntry]
}

enum AuraServerError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case unauthorized
    case networkUnavailable
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Enter a valid backend URL first."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .networkUnavailable:
            return "Network unavailable. Check your connection and try again."
        case .requestFailed(let message):
            return message
        }
    }
}

final class StepTrackingManager {
    static let shared = StepTrackingManager()
    private let healthStore = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable,
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: [stepsType]) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    func fetchTodaySteps() async -> Int? {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let steps = stats?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: Int(steps))
            }
            healthStore.execute(query)
        }
    }
}

actor AuraServerSyncEngine {
    static let shared = AuraServerSyncEngine()

    private func normalizedBaseURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AuraServerError.invalidBaseURL }
        let candidate = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate) else { throw AuraServerError.invalidBaseURL }
        return url
    }

    private func request<Response: Decodable>(
        baseURL: String,
        path: String,
        method: String = "GET",
        token: String? = nil,
        body: Data? = nil
    ) async throws -> Response {
        let base = try normalizedBaseURL(baseURL)
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        // URL.appending(path:) treats its argument as one literal path segment --
        // it percent-encodes "?" rather than treating it as the query delimiter,
        // so a path like "sync/snapshot?groupId=..." silently became a URL with
        // "%3F" baked into the path itself and matched no server route at all.
        // Split off any query string first and attach it properly.
        let pathOnly: String
        let queryString: String?
        if let qIndex = cleanPath.firstIndex(of: "?") {
            pathOnly = String(cleanPath[cleanPath.startIndex..<qIndex])
            queryString = String(cleanPath[cleanPath.index(after: qIndex)...])
        } else {
            pathOnly = cleanPath
            queryString = nil
        }
        var url = base.appending(path: pathOnly)
        if let queryString, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = queryString
            if let composed = components.url {
                url = composed
            }
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            if let netErr = error as? URLError,
               netErr.code == .notConnectedToInternet || netErr.code == .networkConnectionLost || netErr.code == .timedOut {
                throw AuraServerError.networkUnavailable
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuraServerError.invalidResponse
        }
        if http.statusCode == 401 {
            throw AuraServerError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuraServerError.requestFailed(serverErrorMessage(from: data, statusCode: http.statusCode))
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom(Self.decodeServerOrClientDate)
            return try decoder.decode(Response.self, from: data)
        } catch {
            print("[Aurenda] Decode failed for \(Response.self): \(error)")
            throw AuraServerError.invalidResponse
        }
    }

    // A snapshot response mixes two date formats: the envelope's updatedAt is
    // stamped by the server as a JS toISOString() string ("...T09:12:44.123Z"),
    // while every date inside the payload was written by this app's default
    // JSONEncoder as a number (seconds since 2001). The default strategy only
    // reads numbers, so every snapshot pull failed on the envelope; .iso8601
    // alone would fail on every event instead (and on iOS 16 can't parse the
    // milliseconds either). Accept both.
    private static func decodeServerOrClientDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        let raw = try container.decode(String.self)
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(raw)")
    }

    private func request<Body: Encodable, Response: Decodable>(
        baseURL: String,
        path: String,
        method: String,
        token: String? = nil,
        payload: Body
    ) async throws -> Response {
        let data = try JSONEncoder().encode(payload)
        return try await request(baseURL: baseURL, path: path, method: method, token: token, body: data)
    }

    private func serverErrorMessage(from data: Data, statusCode: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] {
            if let string = message as? String {
                return string
            }
            if let payload = try? JSONSerialization.data(withJSONObject: message),
               let string = String(data: payload, encoding: .utf8) {
                return string
            }
        }
        if let fallback = String(data: data, encoding: .utf8), !fallback.isEmpty {
            return fallback
        }
        return "Request failed with status \(statusCode)."
    }

    func register(baseURL: String, email: String, password: String, displayName: String) async throws -> AuraRemoteAuthResponse {
        try await request(
            baseURL: baseURL,
            path: "/auth/register",
            method: "POST",
            payload: ["email": email, "password": password, "displayName": displayName]
        )
    }

    func login(baseURL: String, email: String, password: String) async throws -> AuraRemoteAuthResponse {
        try await request(
            baseURL: baseURL,
            path: "/auth/login",
            method: "POST",
            payload: ["email": email, "password": password]
        )
    }

    func me(baseURL: String, token: String) async throws -> AuraRemoteMeResponse {
        try await request(baseURL: baseURL, path: "/me", token: token)
    }

    func requestPasswordReset(baseURL: String, email: String) async throws -> AuraRemoteOkEnvelope {
        try await request(baseURL: baseURL, path: "/auth/forgot-password", method: "POST", payload: ["email": email])
    }

    func resetPassword(baseURL: String, email: String, code: String, newPassword: String) async throws -> AuraRemoteAuthResponse {
        try await request(
            baseURL: baseURL,
            path: "/auth/reset-password",
            method: "POST",
            payload: ["email": email, "code": code, "newPassword": newPassword]
        )
    }

    func registerDevice(baseURL: String, token: String, deviceToken: String, environment: String) async throws -> AuraRemoteOkEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/me/devices",
            method: "POST",
            token: token,
            payload: ["token": deviceToken, "environment": environment]
        )
    }

    func unregisterDevice(baseURL: String, token: String, deviceToken: String) async throws -> AuraRemoteOkEnvelope {
        try await request(baseURL: baseURL, path: "/me/devices/\(deviceToken)", method: "DELETE", token: token)
    }

    func currentHousehold(baseURL: String, token: String) async throws -> AuraRemoteCurrentHouseholdResponse {
        try await request(baseURL: baseURL, path: "/households/current", token: token)
    }

    func groups(baseURL: String, token: String) async throws -> AuraRemoteGroupsResponse {
        try await request(baseURL: baseURL, path: "/groups", token: token)
    }

    func createGroup(baseURL: String, token: String, name: String, type: String) async throws -> AuraRemoteGroupRecord {
        try await request(
            baseURL: baseURL,
            path: "/groups",
            method: "POST",
            token: token,
            payload: ["name": name, "type": type]
        )
    }

    func joinGroup(baseURL: String, token: String, code: String) async throws -> AuraRemoteGroupRecord {
        try await request(
            baseURL: baseURL,
            path: "/groups/join",
            method: "POST",
            token: token,
            payload: ["code": code]
        )
    }

    func personalMasterCalendar(baseURL: String, token: String) async throws -> AuraRemotePersonalAggregateResponse {
        try await request(baseURL: baseURL, path: "/me/master-calendar", token: token)
    }

    func personalTasks(baseURL: String, token: String) async throws -> AuraRemotePersonalAggregateResponse {
        try await request(baseURL: baseURL, path: "/me/tasks", token: token)
    }

    func personalPlans(baseURL: String, token: String) async throws -> AuraRemotePersonalAggregateResponse {
        try await request(baseURL: baseURL, path: "/me/plans", token: token)
    }

    func personalRoutines(baseURL: String, token: String) async throws -> AuraRemotePersonalAggregateResponse {
        try await request(baseURL: baseURL, path: "/me/routines", token: token)
    }

    func conflictCheck(baseURL: String, token: String) async throws -> AuraRemoteConflictsResponse {
        try await request(baseURL: baseURL, path: "/conflicts/check", method: "POST", token: token, payload: EmptyPayload())
    }

    func conflictIntercept(
        baseURL: String,
        token: String,
        action: String,
        leftEventId: String,
        rightEventId: String,
        preferredEventId: String? = nil
    ) async throws -> AuraRemoteConflictInterceptResponse {
        struct ConflictPayload: Encodable {
            let action: String
            let leftEventId: String
            let rightEventId: String
            let preferredEventId: String?
        }

        return try await request(
            baseURL: baseURL,
            path: "/conflicts/intercept",
            method: "POST",
            token: token,
            payload: ConflictPayload(
                action: action,
                leftEventId: leftEventId,
                rightEventId: rightEventId,
                preferredEventId: preferredEventId
            )
        )
    }

    func uploadSnapshot(baseURL: String, token: String, groupId: String, payload: HouseholdSyncPayload) async throws -> AuraRemoteSnapshotEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/sync/snapshot?groupId=\(groupId)",
            method: "PUT",
            token: token,
            payload: ["payload": payload]
        )
    }

    func downloadSnapshot(baseURL: String, token: String, groupId: String, since: String?) async throws -> AuraRemoteSnapshotEnvelope {
        var path = "/sync/snapshot?groupId=\(groupId)"
        if let since, let encoded = since.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            path += "&since=\(encoded)"
        }
        return try await request(baseURL: baseURL, path: path, token: token)
    }

    func updateProfile(baseURL: String, token: String, displayName: String) async throws -> AuraRemoteUserEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/me/profile",
            method: "PATCH",
            token: token,
            payload: ["displayName": displayName]
        )
    }

    func changePassword(baseURL: String, token: String, currentPassword: String, newPassword: String) async throws -> AuraRemoteOkEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/me/password",
            method: "PATCH",
            token: token,
            payload: ["currentPassword": currentPassword, "newPassword": newPassword]
        )
    }

    func exportAccountData(baseURL: String, token: String) async throws -> Data {
        let base = try normalizedBaseURL(baseURL)
        let url = base.appending(path: "me/export")
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            if let netErr = error as? URLError,
               netErr.code == .notConnectedToInternet || netErr.code == .networkConnectionLost || netErr.code == .timedOut {
                throw AuraServerError.networkUnavailable
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuraServerError.invalidResponse
        }
        if http.statusCode == 401 {
            throw AuraServerError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuraServerError.requestFailed(serverErrorMessage(from: data, statusCode: http.statusCode))
        }
        return data
    }

    func deleteAccount(baseURL: String, token: String, password: String) async throws -> AuraRemoteOkEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/me",
            method: "DELETE",
            token: token,
            payload: ["password": password]
        )
    }

    func groupConflictHistory(baseURL: String, token: String, groupId: String) async throws -> AuraRemoteGroupConflictHistoryResponse {
        try await request(baseURL: baseURL, path: "/groups/\(groupId)/conflicts/history", token: token)
    }

    func groupMembers(baseURL: String, token: String, groupId: String) async throws -> AuraRemoteGroupMembersResponse {
        try await request(baseURL: baseURL, path: "/groups/\(groupId)/members", token: token)
    }

    func groupUpdateMemberRole(baseURL: String, token: String, groupId: String, userId: String, role: String) async throws -> AuraRemoteGroupMembershipEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/groups/\(groupId)/members/\(userId)/role",
            method: "PATCH",
            token: token,
            payload: ["role": role]
        )
    }

    func groupRemoveMember(baseURL: String, token: String, groupId: String, userId: String) async throws -> AuraRemoteOkEnvelope {
        try await request(baseURL: baseURL, path: "/groups/\(groupId)/members/\(userId)", method: "DELETE", token: token)
    }

    func groupTransferOwner(baseURL: String, token: String, groupId: String, userId: String) async throws -> AuraRemoteGroupMembershipEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/groups/\(groupId)/transfer-owner",
            method: "POST",
            token: token,
            payload: ["userId": userId]
        )
    }

    func groupRegenerateCode(baseURL: String, token: String, groupId: String) async throws -> AuraRemoteGroupEnvelope {
        try await request(baseURL: baseURL, path: "/groups/\(groupId)/regenerate-code", method: "POST", token: token, payload: EmptyPayload())
    }

    func renameGroup(baseURL: String, token: String, groupId: String, name: String) async throws -> AuraRemoteGroupEnvelope {
        try await request(
            baseURL: baseURL,
            path: "/groups/\(groupId)",
            method: "PATCH",
            token: token,
            payload: ["name": name]
        )
    }

    func groupAudit(baseURL: String, token: String, groupId: String) async throws -> AuraRemoteAuditResponse {
        try await request(baseURL: baseURL, path: "/groups/\(groupId)/audit", token: token)
    }
}

struct EmptyPayload: Encodable {}
