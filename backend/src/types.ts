export type VisibilityScope = "Personal" | "Family" | "Custom";
export type GroupType = "Family" | "Roommates" | "Couple" | "Church" | "Travel" | "Study" | "Custom";
export type GroupRole = "Owner" | "Admin" | "Member" | "Junior";

export interface User {
  id: string;
  email: string;
  passwordHash: string;
  displayName: string;
  createdAt: string;
}

export interface Membership {
  userId: string;
  householdId: string;
  role: string;
  joinedAt: string;
}

export interface Household {
  id: string;
  name: string;
  code: string;
  createdBy: string;
  createdAt: string;
}

export interface GroupWorkspace {
  id: string;
  name: string;
  type: GroupType;
  code: string;
  createdBy: string;
  createdAt: string;
  legacyHouseholdId?: string;
}

export interface GroupMembership {
  userId: string;
  groupId: string;
  role: GroupRole;
  joinedAt: string;
}

export interface GroupEventRecord {
  id: string;
  groupId: string;
  createdBy: string;
  updatedAt: string;
  payload: Record<string, unknown>;
}

export interface GroupListRecord {
  id: string;
  groupId: string;
  createdBy: string;
  updatedAt: string;
  payload: Record<string, unknown>;
}

export interface GroupPlanRecord {
  id: string;
  groupId: string;
  createdBy: string;
  updatedAt: string;
  payload: Record<string, unknown>;
}

export interface GroupRoutineRecord {
  id: string;
  groupId: string;
  createdBy: string;
  updatedAt: string;
  payload: Record<string, unknown>;
}

export interface HouseholdSnapshot {
  householdId: string;
  updatedAt: string;
  updatedBy: string;
  payload: Record<string, unknown>;
}

export interface HouseholdAuditEntry {
  id: string;
  householdId?: string;
  groupId?: string;
  actorUserId: string;
  action: string;
  targetUserId?: string;
  details?: string;
  createdAt: string;
}

export interface DatabaseShape {
  users: User[];
  memberships: Membership[];
  households: Household[];
  groups: GroupWorkspace[];
  groupMemberships: GroupMembership[];
  groupEvents: GroupEventRecord[];
  groupLists: GroupListRecord[];
  groupPlans: GroupPlanRecord[];
  groupRoutines: GroupRoutineRecord[];
  snapshots: HouseholdSnapshot[];
  audits: HouseholdAuditEntry[];
}