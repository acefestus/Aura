import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

// MARK: - Models

struct EventCategory: Identifiable, Codable, Equatable, Hashable {
    var id         = UUID()
    var name:      String
    var colorHex:  String
    var icon:      String
    var parentId:  UUID?     = nil
    var isCustom:  Bool      = false
    var sound:     AppSound? = nil   // nil = system default

    var color: Color { Color(hex: colorHex) }
    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct CalendarEvent: Identifiable, Codable, Equatable {
    var id               = UUID()
    var title:           String
    var notes:           String       = ""
    var startDate:       Date
    var endDate:         Date
    var isAllDay:        Bool         = false
    var categoryId:      UUID
    var location:        String       = ""
    var alarmMins:       Int          = 15
    var hasAlarm:        Bool         = true
    var url:             String       = ""
    var attachments:     [Attachment] = []
    var recurrence:      Recurrence   = .none
    var soundOverride:   AppSound?    = nil   // nil = use category sound
    var sharedBy:        String?      = nil
    var sharePermission: SharePermission = .edit
    var ownerName:       String       = ""
    var visibility:      VisibilityScope = .family
    var sharedWithNames: [String]     = []
    var assignedMemberIds: [UUID]     = []
    // Optional so payloads written before these existed still decode.
    var createdByUserId: String?      = nil
    var modifiedAt:      Date?        = nil

    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
}

enum SharePermission: String, Codable, CaseIterable {
    case view = "View"
    case edit = "Edit"

    var subtitle: String {
        switch self {
        case .view: return "Receiver can view only"
        case .edit: return "Receiver can edit this event"
        }
    }
}

struct AuraShareEnvelope: Codable {
    var senderName: String
    var permission: SharePermission
    var createdAt: Date
    var events: [CalendarEvent]
}

enum SharedActivityAction: String, Codable, CaseIterable {
    case accepted = "Accepted"
    case inviteSent = "Invite Sent"
    case permissionChanged = "Permission Changed"
    case conflictResolved = "Conflict Resolved"
    case revoked = "Revoked"
}

struct SharedActivityEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp: Date
    var sender: String
    var eventTitle: String
    var action: SharedActivityAction
    var details: String
}

struct DataIntegrityReport {
    var fixedEventTimeRanges = 0
    var repairedCategoryReferences = 0
    var removedInvalidAssignments = 0

    var totalFixes: Int {
        fixedEventTimeRanges + repairedCategoryReferences + removedInvalidAssignments
    }
}

struct GroupMember: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var colorHex: String
    var role: String
    var allowsStepSharing: Bool = false

    var color: Color { Color(hex: colorHex) }
}

enum VisibilityScope: String, Codable, CaseIterable {
    case personal = "Personal"
    case family = "Family"
    case custom = "Custom"

    var icon: String {
        switch self {
        case .personal: return "person.fill"
        case .family: return "person.3.fill"
        case .custom: return "person.2.badge.gearshape.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .personal: return "Only you can see this"
        case .family: return "Visible to everyone in this workspace"
        case .custom: return "Visible to selected members"
        }
    }

    /// User-facing label. Kept separate from rawValue (which stays "Family" for
    /// backward compatibility with already-persisted/synced data) since this app's
    /// groups aren't always families -- the same option applies to a Church group,
    /// a Roommates group, etc., so the visible text shouldn't assume otherwise.
    var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .family: return "Whole Group"
        case .custom: return "Custom"
        }
    }
}

enum GroupActivityKind: String, Codable, CaseIterable {
    case walk = "Walk"
    case run = "Run"
    case play = "Play"
    case sport = "Sport"
    case school = "School"
    case church = "Church"
    case other = "Other"

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .play: return "gamecontroller.fill"
        case .sport: return "figure.soccer"
        case .school: return "book.closed.fill"
        case .church: return "building.columns.fill"
        case .other: return "sparkles"
        }
    }
}

struct GroupActivity: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: GroupActivityKind
    var date: Date
    var durationMinutes: Int
    var notes: String
    var participantIds: [UUID]
    var ownerName: String = ""
    var visibility: VisibilityScope = .family
    var sharedWithNames: [String] = []
}

enum GroupListKind: String, Codable, CaseIterable {
    case supermarket = "Supermarket"
    case pharmacy = "Pharmacy"
    case chores = "Chores"
    case pantry = "Pantry"
    case meals = "Meals"
    case other = "Other"

    var icon: String {
        switch self {
        case .supermarket: return "cart.fill"
        case .pharmacy: return "cross.case.fill"
        case .chores: return "checklist"
        case .pantry: return "shippingbox.fill"
        case .meals: return "fork.knife"
        case .other: return "list.bullet"
        }
    }
}

struct GroupListItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var quantity: String
    var note: String
    var isDone: Bool
    var assignedMemberId: UUID?
    var preferredStore: String? = nil
    var dueDate: Date? = nil
    var completedByName: String? = nil
    var boughtAt: Date? = nil
    var createdByUserId: String? = nil
    var modifiedAt: Date? = nil
}

struct GroupList: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var kind: GroupListKind
    var createdAt: Date
    var items: [GroupListItem]
    var ownerName: String = ""
    var visibility: VisibilityScope = .family
    var sharedWithNames: [String] = []
    var createdByUserId: String? = nil
    var modifiedAt: Date? = nil
}

/// A multi-step project with a target date -- distinct from a CalendarEvent
/// (one dated occurrence) and a routine (a recurring event). Reuses
/// GroupListItem for its checklist steps rather than inventing a parallel
/// item type.
struct GroupPlan: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var targetDate: Date
    var notes: String = ""
    var createdAt: Date
    var items: [GroupListItem]
    var ownerName: String = ""
    var visibility: VisibilityScope = .family
    var sharedWithNames: [String] = []
    var createdByUserId: String? = nil
    var modifiedAt: Date? = nil

    var progress: Double {
        guard !items.isEmpty else { return 0 }
        return Double(items.filter(\.isDone).count) / Double(items.count)
    }
}

/// A shop items can be bought at. Each group builds its own list.
struct GroupStore: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var createdByUserId: String? = nil
    var modifiedAt: Date? = nil
}

/// A member's suggested change to something someone else created. Only the
/// creator can approve (which applies it) or decline it.
struct EditProposal: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case event, listItem, planItem, listTitle, planTitle }
    enum Status: String, Codable { case pending, approved, declined, withdrawn }

    var id = UUID()
    var kind: Kind
    var targetId: UUID
    /// The list or plan an item belongs to.
    var parentId: UUID? = nil
    var targetTitle: String
    var proposedEvent: CalendarEvent? = nil
    var proposedItem: GroupListItem? = nil
    var proposedTitle: String? = nil
    var proposerUserId: String
    var proposerName: String
    var targetOwnerUserId: String? = nil
    var targetOwnerName: String
    var status: Status = .pending
    var createdAt: Date
    var resolvedAt: Date? = nil
    var modifiedAt: Date? = nil
}

struct GroupStepSnapshot: Identifiable, Codable, Equatable {
    var id = UUID()
    var ownerName: String
    var date: Date
    var steps: Int
    var visibility: VisibilityScope = .personal
    var sharedWithNames: [String] = []
    var updatedAt: Date = Date()
}

struct LiveGroupActivitySession: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: GroupActivityKind
    var startedAt: Date
    var notes: String
    var participantIds: [UUID]
    var ownerName: String
    var visibility: VisibilityScope
    var sharedWithNames: [String]
}

struct HouseholdSyncPayload: Codable {
    var updatedAt: Date
    var updatedBy: String
    var categories: [EventCategory]
    var events: [CalendarEvent]
    var members: [GroupMember]
    var groupLists: [GroupList]
    var groupActivities: [GroupActivity]
    var stepSnapshots: [GroupStepSnapshot]
    var groupPlans: [GroupPlan] = []
    var stores: [GroupStore] = []
    var proposals: [EditProposal] = []
    /// Deleted record id -> when. A record missing from a snapshot only means
    /// that device never had it; a tombstone is what makes a delete stick.
    var deletedIds: [String: Date] = [:]

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case updatedBy
        case categories
        case events
        case members
        case groupLists
        case groupActivities
        case stepSnapshots
        case familyLists
        case familyActivities
        case groupPlans
        case stores
        case proposals
        case deletedIds
    }

    init(
        updatedAt: Date,
        updatedBy: String,
        categories: [EventCategory],
        events: [CalendarEvent],
        members: [GroupMember],
        groupLists: [GroupList],
        groupActivities: [GroupActivity],
        stepSnapshots: [GroupStepSnapshot],
        groupPlans: [GroupPlan] = [],
        stores: [GroupStore] = [],
        proposals: [EditProposal] = [],
        deletedIds: [String: Date] = [:]
    ) {
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.categories = categories
        self.events = events
        self.members = members
        self.groupLists = groupLists
        self.groupActivities = groupActivities
        self.stepSnapshots = stepSnapshots
        self.groupPlans = groupPlans
        self.stores = stores
        self.proposals = proposals
        self.deletedIds = deletedIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        updatedBy = try container.decode(String.self, forKey: .updatedBy)
        categories = try container.decode([EventCategory].self, forKey: .categories)
        events = try container.decode([CalendarEvent].self, forKey: .events)
        members = try container.decode([GroupMember].self, forKey: .members)
        groupLists = try container.decodeIfPresent([GroupList].self, forKey: .groupLists)
            ?? container.decodeIfPresent([GroupList].self, forKey: .familyLists)
            ?? []
        groupActivities = try container.decodeIfPresent([GroupActivity].self, forKey: .groupActivities)
            ?? container.decodeIfPresent([GroupActivity].self, forKey: .familyActivities)
            ?? []
        stepSnapshots = try container.decodeIfPresent([GroupStepSnapshot].self, forKey: .stepSnapshots) ?? []
        groupPlans = try container.decodeIfPresent([GroupPlan].self, forKey: .groupPlans) ?? []
        stores = try container.decodeIfPresent([GroupStore].self, forKey: .stores) ?? []
        proposals = try container.decodeIfPresent([EditProposal].self, forKey: .proposals) ?? []
        deletedIds = try container.decodeIfPresent([String: Date].self, forKey: .deletedIds) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(updatedBy, forKey: .updatedBy)
        try container.encode(categories, forKey: .categories)
        try container.encode(events, forKey: .events)
        try container.encode(members, forKey: .members)
        // Keep legacy keys for server/storage compatibility during migration.
        try container.encode(groupLists, forKey: .familyLists)
        try container.encode(groupActivities, forKey: .familyActivities)
        try container.encode(stepSnapshots, forKey: .stepSnapshots)
        try container.encode(groupPlans, forKey: .groupPlans)
        try container.encode(stores, forKey: .stores)
        try container.encode(proposals, forKey: .proposals)
        try container.encode(deletedIds, forKey: .deletedIds)
    }
}
