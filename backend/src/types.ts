export type VisibilityScope = "Personal" | "Family" | "Custom";

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

export interface HouseholdSnapshot {
  householdId: string;
  updatedAt: string;
  updatedBy: string;
  payload: Record<string, unknown>;
}

export interface DatabaseShape {
  users: User[];
  memberships: Membership[];
  households: Household[];
  snapshots: HouseholdSnapshot[];
}