# Aura V2 Upgrade Plan

Status: Draft for implementation kickoff
Date: 2026-07-01
Product direction: Shared Life, Organized

## Implementation Status

- Chunk 1 completed: backend data model now includes group workspaces and group memberships.
- Chunk 2 completed: backend group APIs added for list/create/join/group members/role updates.
- Chunk 3 completed: iOS client models and sync engine methods added for group endpoints.
- Chunk 4 completed: backend workspace data endpoints added for group events/lists/plans/routines.
- Chunk 5 completed: iOS network client methods added for group events/lists/plans/routines.
- Chunk 6 completed: iOS auth/setup flow upgraded to group-first create/join with active group selection.
- Chunk 7 completed: backend personal-layer aggregate endpoints added (`/me/master-calendar`, `/me/tasks`, `/me/plans`, `/me/routines`, `/me/conflicts`).
- Chunk 8 completed: iOS client models and methods added for personal-layer aggregate endpoints.
- Chunk 9 completed: iOS main shell now includes an active group switcher menu overlay for fast workspace switching.
- Chunk 10 completed: iOS Personal tab now renders Master Calendar, My Tasks, My Plans, My Routines, and Conflicts from /me aggregate endpoints.
- Chunk 11 completed: Personal tab rows now support source-item tap-through (event/list where resolvable) and conflict CTA actions (Fix now, Suggest slot, Accept anyway).
- Chunk 12 completed: tokenized UI fidelity pass across shared primitives (typography, spacing, radius, elevation, motion) and applied to Auth/Home/Personal shared components.
- Chunk 13 completed: senior-designer fidelity enhancement without Figma reference (atmospheric backgrounds, glass-card surfaces, shared interactive press-state style, and component consistency refinements).
- Chunk 14 completed: backend conflict-intercept endpoint (`/conflicts/intercept`) and server-backed conflict resolution workflow for Personal CTA actions (Fix now/Suggest slot/Accept anyway), including reconciling a server-side "fix" back into the local event the user actually sees.
- Chunk 15 completed: group-scoped admin endpoints (remove member, transfer owner, regenerate join code, audit log) plus an iOS Group Members screen wired to them.
- Chunk 16 completed: local write path for group events/lists/routines so the Personal tab aggregates and conflict detection have real data instead of permanently-empty reads; recurring events also mirror into group routines.
- Chunk 17 completed: local Plan model (multi-step project with a target date) with full create/view/checklist UI, closing the last permanently-empty Personal tab section.
- Known gap, not yet scheduled: the widget extension still reads a single flat local snapshot and has no concept of groups or the personal-layer aggregate.

## 1) Executive Direction

Aura V2 upgrades the current single-household product into a true multi-group coordination platform.

Each user can belong to multiple isolated groups (family, roommates, church, travel, study, custom), while still getting one private personal layer that merges everything relevant to them.

## 2) Where We Are vs Target

Current state (V1.1):
- One user -> one household membership in backend.
- One household snapshot document for all shared data.
- iOS store and sync logic centered around household concepts.
- Visibility levels exist (Personal, Family, Custom) but semantics are family-only.

Target state (V2):
- One user -> many group memberships.
- Group workspaces are isolated by design.
- Personal Master Layer merges cross-group user-relevant data.
- Smart conflict intercept evaluates overlaps across all groups involving the user.
- Group roles expanded to Owner, Admin, Member, Junior.

## 3) V2 Domain Model

### Core entities
- User
- GroupWorkspace
- GroupMembership
- CalendarEvent
- GroupList
- GroupPlan
- GroupRoutine
- NotificationItem
- ConflictRecord

### Key relationships
- User 1..* GroupMembership
- GroupWorkspace 1..* GroupMembership
- GroupWorkspace owns calendar/lists/plans/routines in isolation
- Personal Master Layer is computed per user from items assigned or visible to that user

### Visibility model
- Personal: only item owner/creator
- Group: all members of owning group
- Custom: explicit allow-list of member ids within owning group

Important rule:
- Visibility never crosses group boundaries.

## 4) Backend Upgrade Design

## 4.1 Storage evolution

Move from household snapshot to workspace-scoped records.

Required new collections/tables:
- groups
- group_memberships
- group_events
- group_lists
- group_plans
- group_routines
- user_personal_items (optional if personal items are first-class)
- notifications
- conflict_logs

Keep existing collections for migration compatibility:
- households (legacy alias of first group type family)
- snapshots (legacy import/export only)

## 4.2 API evolution

New endpoints (summary):
- POST /groups
- GET /groups
- GET /groups/:groupId
- POST /groups/:groupId/join
- POST /groups/:groupId/invite
- GET /groups/:groupId/members
- PATCH /groups/:groupId/members/:userId/role

Workspace data endpoints:
- GET/POST /groups/:groupId/events
- GET/POST /groups/:groupId/lists
- GET/POST /groups/:groupId/plans
- GET/POST /groups/:groupId/routines

Personal layer endpoints:
- GET /me/master-calendar
- GET /me/tasks
- GET /me/plans
- GET /me/routines
- GET /me/conflicts

Smart layer endpoints:
- POST /conflicts/check
- POST /conflicts/intercept
- GET /suggestions/time-slots

Compatibility endpoints (temporary):
- Keep /households and /sync/snapshot as legacy bridge until migration is complete.

## 4.3 Auth and permissions

Roles per group:
- Owner: full control + transfer ownership
- Admin: member and content administration
- Member: standard create/edit permissions
- Junior: constrained permissions (no destructive admin actions)

Enforcement rules:
- permissions are evaluated within group scope only
- role checks happen on every group-scoped write endpoint

## 5) iOS App Upgrade Design

## 5.1 State architecture

Current single EventStore must be split into:
- GroupStore (active workspace state)
- PersonalStore (master merged data)
- SyncStore (network + offline queue + retry)

Add explicit active group context:
- activeGroupId
- group switcher with quick swipe/dropdown

## 5.2 UX upgrades

Onboarding V2:
1. Create account
2. Create first group (type selection)
3. Invite or skip
4. Add first event/list/plan
5. Master calendar walkthrough

Navigation:
- Group workspace views remain isolated
- Personal tab shows merged cross-group data for current user

Conflict intercept modal:
- Trigger on create/edit/accept event
- Show conflicting items grouped by group name
- Offer: Accept anyway, Fix conflict, View alternatives

## 5.3 Widgets V2

Add/extend widgets:
- Countdown (per selected group or personal aggregate)
- Next events calendar widget
- My tasks today widget
- Routine today widget

Widget data strategy:
- Store per-group slices in App Group storage
- Also store computed personal aggregate snapshot for fast widget rendering

## 6) Migration Plan (No Data Loss)

Phase M1: Dual-write bridge
- Keep legacy household snapshot writes.
- Also write transformed group documents.

Phase M2: Backfill
- Convert existing household to a first group workspace of type family.
- Convert membership role mapping Owner/Member to new role set.
- Convert snapshot payload objects to workspace documents.

Phase M3: Read switch
- iOS app reads from new group endpoints first.
- Fallback to legacy snapshot only when new data absent.

Phase M4: Legacy sunset
- Disable legacy writes after stability window.
- Remove legacy endpoints in a major-version cut.

## 7) Delivery Phases

Phase 1: Core architecture
- multi-group backend data model
- group CRUD + membership roles
- iOS group selector and active workspace context

Phase 2: Personal master layer
- merged master calendar
- merged my tasks/my plans/my routines
- personal filters

Phase 3: Conflict and smart layer
- cross-group conflict intercept
- severity model (soft/hard/critical)
- suggestion engine for alternative slots

Phase 4: Notifications and widgets
- notification bundling
- daily digest
- full widget suite upgrades

Phase 5: Stabilization
- performance tuning
- migration completion
- release readiness and QA hardening

## 8) Acceptance Criteria for V2 Launch

Must-have:
- user can belong to multiple groups
- no cross-group data leakage
- personal master calendar merges correctly
- conflict intercept checks all relevant groups
- role enforcement works for Owner/Admin/Member/Junior
- migration preserves all existing household data

Quality targets:
- zero known P0 privacy bugs
- no data-loss regressions in migration tests
- responsive calendar interactions on iOS baseline devices

## 9) Immediate Engineering Tasks (Next Sprint)

1. Backend: introduce GroupWorkspace and GroupMembership models while preserving legacy endpoints.
2. Backend: add GET /groups and POST /groups with role-aware membership creation.
3. iOS: add active group selector state and workspace switcher shell.
4. iOS: refactor family-specific naming toward group-generic domain naming.
5. Backend + iOS: implement compatibility mapper between household payload and first group workspace.
6. QA: create migration fixtures from real sample household snapshots.

## 10) Product Messaging Update

Aura V2 messaging:
- premium shared organizer for multiple life circles
- private group workspaces with one personal command center
- proactive conflict prevention across your shared life
