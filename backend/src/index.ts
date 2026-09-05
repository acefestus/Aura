import "dotenv/config";
import path from "node:path";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { v4 as uuidv4 } from "uuid";
import { z } from "zod";
import { JsonStore } from "./store.js";
import { PgStore } from "./pgStore.js";
import type {
  DatabaseShape,
  GroupEventRecord,
  GroupListRecord,
  GroupMembership,
  GroupPlanRecord,
  GroupRole,
  GroupRoutineRecord,
  GroupType,
  GroupWorkspace,
  HouseholdAuditEntry,
  HouseholdSnapshot,
  Membership,
  User
} from "./types.js";

const app = express();
const port = Number(process.env.PORT ?? 4000);
const jwtSecret = process.env.JWT_SECRET ?? "";
const jwtIssuer = process.env.JWT_ISSUER ?? "aura-family-backend";
const jwtAudience = process.env.JWT_AUDIENCE ?? "aura-family-clients";
const dataFile = process.env.DATA_FILE ?? "./data/db.json";
const webRoot = path.resolve(process.cwd(), "public");
const allowedOrigins = new Set(
  (process.env.CORS_ALLOWED_ORIGINS ?? "")
    .split(",")
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0)
);
const disableOriginCheck = process.env.CORS_DISABLE_ORIGIN_CHECK === "true";
const adminEmails = new Set(
  (process.env.ADMIN_EMAILS ?? process.env.ADMIN_EMAIL ?? "")
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter((email) => email.length > 0)
);
const databaseUrl = process.env.DATABASE_URL;
const store = databaseUrl ? new PgStore(databaseUrl) : new JsonStore(dataFile);

if (jwtSecret.length < 32 || jwtSecret.toLowerCase() === "change-me") {
  throw new Error("JWT_SECRET must be set and at least 32 characters long.");
}

if (!disableOriginCheck && allowedOrigins.size === 0) {
  throw new Error("CORS_ALLOWED_ORIGINS must be set when CORS_DISABLE_ORIGIN_CHECK is not true.");
}

app.set("trust proxy", 1);
app.use(
  helmet({
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: { policy: "cross-origin" }
  })
);
app.use(
  cors({
    origin(origin, callback) {
      if (!origin) {
        callback(null, true);
        return;
      }
      if (disableOriginCheck || allowedOrigins.has(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error("Origin not allowed by CORS policy"));
    },
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    credentials: false,
    allowedHeaders: ["Content-Type", "Authorization"]
  })
);
app.use(express.json({ limit: "2mb" }));
app.use(express.static(webRoot));

const authLimiter = rateLimit({
  windowMs: Number(process.env.RATE_LIMIT_AUTH_WINDOW_MS ?? 15 * 60 * 1000),
  max: Number(process.env.RATE_LIMIT_AUTH_MAX ?? 10),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many authentication attempts. Try again later." }
});

const writeLimiter = rateLimit({
  windowMs: Number(process.env.RATE_LIMIT_WRITE_WINDOW_MS ?? 60 * 1000),
  max: Number(process.env.RATE_LIMIT_WRITE_MAX ?? 120),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many requests. Slow down and try again." }
});

const adminLimiter = rateLimit({
  windowMs: Number(process.env.RATE_LIMIT_ADMIN_WINDOW_MS ?? 60 * 1000),
  max: Number(process.env.RATE_LIMIT_ADMIN_MAX ?? 60),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many admin requests. Try again shortly." }
});

app.use("/auth", authLimiter);
app.use("/admin", adminLimiter);
app.use(["/sync", "/households", "/groups", "/me", "/conflicts"], writeLimiter);

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  displayName: z.string().min(1)
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1)
});

const householdSchema = z.object({
  name: z.string().min(1)
});

const groupSchema = z.object({
  name: z.string().min(1),
  type: z.enum(["Family", "Roommates", "Couple", "Church", "Travel", "Study", "Custom"]).default("Custom")
});

const joinSchema = z.object({
  code: z.string().min(4)
});

const snapshotSchema = z.object({
  payload: z.record(z.unknown())
});

const groupPayloadSchema = z.object({
  payload: z.record(z.unknown())
});

const conflictInterceptSchema = z.object({
  action: z.enum(["fix", "suggest", "accept"]),
  leftEventId: z.string().min(1),
  rightEventId: z.string().min(1),
  preferredEventId: z.string().min(1).optional()
});

const updateProfileSchema = z.object({
  displayName: z.string().min(1)
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8)
});

const adminRoleSchema = z.object({
  role: z.enum(["Owner", "Admin", "Member", "Junior"])
});

const transferOwnerSchema = z.object({
  userId: z.string().min(1)
});

type AuthRequest = express.Request & { userId?: string };

function isConfiguredAdminEmail(email: string) {
  return adminEmails.has(email.trim().toLowerCase());
}

function enforceAdminOwnerMembership(db: Awaited<ReturnType<typeof store.read>>, userId: string) {
  const user = db.users.find((candidate) => candidate.id === userId);
  if (!user || !isConfiguredAdminEmail(user.email)) {
    return false;
  }

  const membership = db.memberships.find((candidate) => candidate.userId === userId);
  if (!membership || membership.role === "Owner") {
    return false;
  }

  membership.role = "Owner";
  return true;
}

function logAuditEntry(
  db: DatabaseShape,
  actorUserId: string,
  householdId: string,
  action: string,
  options: { targetUserId?: string; details?: string } = {}
) {
  const entry: HouseholdAuditEntry = {
    id: uuidv4(),
    actorUserId,
    householdId,
    action,
    targetUserId: options.targetUserId,
    details: options.details,
    createdAt: new Date().toISOString()
  };
  db.audits.push(entry);
}

function randomHouseholdCode() {
  return Math.random().toString(36).slice(2, 8).toUpperCase();
}

function normalizeRole(role: string): GroupRole {
  switch (role) {
    case "Owner":
      return "Owner";
    case "Admin":
      return "Admin";
    case "Junior":
      return "Junior";
    default:
      return "Member";
  }
}

function ensureLegacyGroups(db: DatabaseShape): boolean {
  let changed = false;

  for (const household of db.households) {
    const existingGroup = db.groups.find(
      (group) => group.id === household.id || group.legacyHouseholdId === household.id
    );
    if (!existingGroup) {
      const group: GroupWorkspace = {
        id: household.id,
        name: household.name,
        type: "Family",
        code: household.code,
        createdBy: household.createdBy,
        createdAt: household.createdAt,
        legacyHouseholdId: household.id
      };
      db.groups.push(group);
      changed = true;
    }
  }

  for (const membership of db.memberships) {
    const groupId = membership.householdId;
    const existing = db.groupMemberships.find(
      (candidate) => candidate.userId === membership.userId && candidate.groupId === groupId
    );
    if (!existing) {
      const groupMembership: GroupMembership = {
        userId: membership.userId,
        groupId,
        role: normalizeRole(membership.role),
        joinedAt: membership.joinedAt
      };
      db.groupMemberships.push(groupMembership);
      changed = true;
    }
  }

  return changed;
}

async function readDbWithGroupBridge() {
  const db = await store.read();
  const changed = ensureLegacyGroups(db);
  if (changed) {
    await store.write(db);
  }
  return db;
}

async function getOwnerContext(req: AuthRequest, res: express.Response) {
  const db = await store.read();
  const userId = req.userId!;
  const _ = enforceAdminOwnerMembership(db, userId);
  const membership = db.memberships.find((candidate) => candidate.userId === userId);
  if (!membership) {
    res.status(404).json({ error: "No household membership" });
    return null;
  }
  if (membership.role !== "Owner") {
    res.status(403).json({ error: "Owner role required" });
    return null;
  }

  const household = db.households.find((candidate) => candidate.id === membership.householdId);
  if (!household) {
    res.status(404).json({ error: "Household not found" });
    return null;
  }

  return { db, userId, membership, household };
}

type GroupMemberContext = {
  db: DatabaseShape;
  group: GroupWorkspace;
  membership: GroupMembership;
  userId: string;
};

async function getGroupMemberContext(
  req: AuthRequest,
  res: express.Response,
  requiredRoles: GroupRole[] = ["Owner", "Admin", "Member", "Junior"]
): Promise<GroupMemberContext | null> {
  const groupIdParam = req.params.groupId;
  const groupId = Array.isArray(groupIdParam) ? groupIdParam[0] : groupIdParam;
  if (!groupId) {
    res.status(400).json({ error: "Missing group id" });
    return null;
  }

  const db = await readDbWithGroupBridge();
  const userId = req.userId!;
  const group = db.groups.find((candidate) => candidate.id === groupId);
  if (!group) {
    res.status(404).json({ error: "Group not found" });
    return null;
  }

  const membership = db.groupMemberships.find(
    (candidate) => candidate.groupId === groupId && candidate.userId === userId
  );
  if (!membership) {
    res.status(403).json({ error: "Not a member of this group" });
    return null;
  }

  if (!requiredRoles.includes(membership.role)) {
    res.status(403).json({ error: "Insufficient permissions" });
    return null;
  }

  return { db, group, membership, userId };
}

async function getUserGroupsContext(req: AuthRequest) {
  const db = await readDbWithGroupBridge();
  const userId = req.userId!;
  const memberships = db.groupMemberships.filter((candidate) => candidate.userId === userId);
  const groupIds = new Set(memberships.map((candidate) => candidate.groupId));
  const groups = db.groups.filter((candidate) => groupIds.has(candidate.id));
  return { db, userId, memberships, groups, groupIds };
}

function parseEventWindow(record: GroupEventRecord) {
  const startDate = Date.parse(String(record.payload.startDate ?? ""));
  const endDate = Date.parse(String(record.payload.endDate ?? ""));
  if (Number.isNaN(startDate) || Number.isNaN(endDate) || endDate <= startDate) {
    return null;
  }
  return { startDate, endDate };
}

function conflictsWithAny(target: GroupEventRecord, candidates: GroupEventRecord[]) {
  const targetWindow = parseEventWindow(target);
  if (!targetWindow) {
    return [] as GroupEventRecord[];
  }

  return candidates.filter((candidate) => {
    if (candidate.id === target.id) {
      return false;
    }
    const window = parseEventWindow(candidate);
    if (!window) {
      return false;
    }
    return targetWindow.startDate < window.endDate && window.startDate < targetWindow.endDate;
  });
}

function suggestedStartISO(target: GroupEventRecord, candidates: GroupEventRecord[]) {
  const window = parseEventWindow(target);
  if (!window) {
    return null;
  }

  const duration = window.endDate - window.startDate;
  let proposedStart = window.startDate;
  for (let attempt = 0; attempt < 96; attempt += 1) {
    const probe: GroupEventRecord = {
      ...target,
      payload: {
        ...target.payload,
        startDate: new Date(proposedStart).toISOString(),
        endDate: new Date(proposedStart + duration).toISOString()
      }
    };
    const overlaps = conflictsWithAny(probe, candidates);
    if (overlaps.length === 0) {
      return new Date(proposedStart).toISOString();
    }
    const latestEnd = overlaps
      .map((entry) => parseEventWindow(entry)?.endDate ?? 0)
      .reduce((max, value) => Math.max(max, value), 0);
    proposedStart = latestEnd > 0 ? latestEnd + 15 * 60 * 1000 : proposedStart + 15 * 60 * 1000;
  }

  return null;
}

function eventTitle(record: GroupEventRecord) {
  const title = record.payload.title;
  return typeof title === "string" && title.trim().length > 0 ? title.trim() : "Untitled event";
}

function logConflictAuditEntry(
  db: DatabaseShape,
  actorUserId: string,
  groupId: string,
  action: "conflict_acknowledged" | "conflict_suggested" | "conflict_fixed",
  leftEventId: string,
  rightEventId: string,
  details: Record<string, unknown> = {}
) {
  logAuditEntry(db, actorUserId, groupId, action, {
    details: JSON.stringify({ leftEventId, rightEventId, ...details })
  });
}

function signToken(userId: string) {
  return jwt.sign({ sub: userId }, jwtSecret, {
    expiresIn: "30d",
    issuer: jwtIssuer,
    audience: jwtAudience
  });
}

function requireAuth(req: AuthRequest, res: express.Response, next: express.NextFunction) {
  const auth = req.header("authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) {
    res.status(401).json({ error: "Missing token" });
    return;
  }
  try {
    const decoded = jwt.verify(token, jwtSecret, {
      issuer: jwtIssuer,
      audience: jwtAudience
    }) as { sub: string };
    req.userId = decoded.sub;
    next();
  } catch {
    res.status(401).json({ error: "Invalid token" });
  }
}

app.get("/health", async (_req, res) => {
  res.json({ ok: true, service: "aura-family-backend" });
});

app.post("/auth/register", async (req, res) => {
  const parsed = registerSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const { email, password, displayName } = parsed.data;
  const db = await store.read();
  if (db.users.some((user) => user.email.toLowerCase() === email.toLowerCase())) {
    res.status(409).json({ error: "Email already exists" });
    return;
  }

  const user: User = {
    id: uuidv4(),
    email,
    passwordHash: await bcrypt.hash(password, 10),
    displayName,
    createdAt: new Date().toISOString()
  };

  db.users.push(user);
  await store.write(db);
  res.status(201).json({ token: signToken(user.id), user: { id: user.id, email, displayName } });
});

app.post("/auth/login", async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const { email, password } = parsed.data;
  const db = await store.read();
  const user = db.users.find((candidate) => candidate.email.toLowerCase() === email.toLowerCase());
  if (!user) {
    res.status(401).json({ error: "Invalid credentials" });
    return;
  }
  const matches = await bcrypt.compare(password, user.passwordHash);
  if (!matches) {
    res.status(401).json({ error: "Invalid credentials" });
    return;
  }

  if (enforceAdminOwnerMembership(db, user.id)) {
    await store.write(db);
  }

  res.json({ token: signToken(user.id), user: { id: user.id, email: user.email, displayName: user.displayName } });
});

app.get("/me", requireAuth, async (req: AuthRequest, res) => {
  const db = await store.read();
  let dbUpdated = enforceAdminOwnerMembership(db, req.userId!);
  const user = db.users.find((candidate) => candidate.id === req.userId);
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }

  const membership = db.memberships.find((m) => m.userId === user.id) ?? null;
  if (dbUpdated) {
    await store.write(db);
  }
  res.json({
    user: { id: user.id, email: user.email, displayName: user.displayName },
    membership,
    isAdmin: isConfiguredAdminEmail(user.email)
  });
});

app.get("/me/master-calendar", requireAuth, async (req: AuthRequest, res) => {
  const context = await getUserGroupsContext(req);
  const items = context.db.groupEvents
    .filter((candidate) => context.groupIds.has(candidate.groupId))
    .map((candidate) => ({
      ...candidate,
      group: context.groups.find((group) => group.id === candidate.groupId) ?? null
    }))
    .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));

  res.json({ items, total: items.length });
});

app.get("/me/tasks", requireAuth, async (req: AuthRequest, res) => {
  const context = await getUserGroupsContext(req);
  const items = context.db.groupLists
    .filter((candidate) => context.groupIds.has(candidate.groupId))
    .map((candidate) => ({
      ...candidate,
      group: context.groups.find((group) => group.id === candidate.groupId) ?? null
    }))
    .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));

  res.json({ items, total: items.length });
});

app.get("/me/plans", requireAuth, async (req: AuthRequest, res) => {
  const context = await getUserGroupsContext(req);
  const items = context.db.groupPlans
    .filter((candidate) => context.groupIds.has(candidate.groupId))
    .map((candidate) => ({
      ...candidate,
      group: context.groups.find((group) => group.id === candidate.groupId) ?? null
    }))
    .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));

  res.json({ items, total: items.length });
});

app.get("/me/routines", requireAuth, async (req: AuthRequest, res) => {
  const context = await getUserGroupsContext(req);
  const items = context.db.groupRoutines
    .filter((candidate) => context.groupIds.has(candidate.groupId))
    .map((candidate) => ({
      ...candidate,
      group: context.groups.find((group) => group.id === candidate.groupId) ?? null
    }))
    .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));

  res.json({ items, total: items.length });
});

app.get("/me/conflicts", requireAuth, async (req: AuthRequest, res) => {
  const context = await getUserGroupsContext(req);
  const events = context.db.groupEvents
    .filter((candidate) => context.groupIds.has(candidate.groupId))
    .sort((left, right) => left.updatedAt.localeCompare(right.updatedAt));

  const conflicts: Array<{ leftEventId: string; rightEventId: string; severity: "Soft" | "Hard" | "Critical" }> = [];
  for (let index = 0; index < events.length; index += 1) {
    const current = events[index];
    if (!current) {
      continue;
    }
    const currentStart = Date.parse(String(current.payload.startDate ?? ""));
    const currentEnd = Date.parse(String(current.payload.endDate ?? ""));
    if (Number.isNaN(currentStart) || Number.isNaN(currentEnd)) {
      continue;
    }

    for (let nextIndex = index + 1; nextIndex < events.length; nextIndex += 1) {
      const next = events[nextIndex];
      if (!next) {
        continue;
      }
      const nextStart = Date.parse(String(next.payload.startDate ?? ""));
      const nextEnd = Date.parse(String(next.payload.endDate ?? ""));
      if (Number.isNaN(nextStart) || Number.isNaN(nextEnd)) {
        continue;
      }
      const overlaps = currentStart < nextEnd && nextStart < currentEnd;
      if (!overlaps) {
        continue;
      }

      const overlapMs = Math.min(currentEnd, nextEnd) - Math.max(currentStart, nextStart);
      let severity: "Soft" | "Hard" | "Critical" = "Soft";
      if (overlapMs >= 90 * 60 * 1000) {
        severity = "Critical";
      } else if (overlapMs >= 30 * 60 * 1000) {
        severity = "Hard";
      }

      conflicts.push({ leftEventId: current.id, rightEventId: next.id, severity });
    }
  }

  res.json({ conflicts, total: conflicts.length });
});

app.post("/conflicts/check", requireAuth, async (req: AuthRequest, res) => {
  const context = await getUserGroupsContext(req);
  const events = context.db.groupEvents
    .filter((candidate) => context.groupIds.has(candidate.groupId))
    .sort((left, right) => left.updatedAt.localeCompare(right.updatedAt));

  const conflicts: Array<{
    leftEventId: string;
    rightEventId: string;
    leftEventTitle: string;
    rightEventTitle: string;
    severity: "Soft" | "Hard" | "Critical";
  }> = [];
  for (let index = 0; index < events.length; index += 1) {
    const current = events[index];
    if (!current) {
      continue;
    }
    const currentWindow = parseEventWindow(current);
    if (!currentWindow) {
      continue;
    }

    for (let nextIndex = index + 1; nextIndex < events.length; nextIndex += 1) {
      const next = events[nextIndex];
      if (!next) {
        continue;
      }
      const nextWindow = parseEventWindow(next);
      if (!nextWindow) {
        continue;
      }

      const overlaps = currentWindow.startDate < nextWindow.endDate && nextWindow.startDate < currentWindow.endDate;
      if (!overlaps) {
        continue;
      }

      const overlapMs = Math.min(currentWindow.endDate, nextWindow.endDate) - Math.max(currentWindow.startDate, nextWindow.startDate);
      let severity: "Soft" | "Hard" | "Critical" = "Soft";
      if (overlapMs >= 90 * 60 * 1000) {
        severity = "Critical";
      } else if (overlapMs >= 30 * 60 * 1000) {
        severity = "Hard";
      }

      conflicts.push({
        leftEventId: current.id,
        rightEventId: next.id,
        leftEventTitle: typeof current.payload.title === "string" ? current.payload.title : "Untitled event",
        rightEventTitle: typeof next.payload.title === "string" ? next.payload.title : "Untitled event",
        severity
      });
    }
  }

  res.json({ conflicts, total: conflicts.length });
});

app.post("/conflicts/intercept", requireAuth, async (req: AuthRequest, res) => {
  const parsed = conflictInterceptSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const context = await getUserGroupsContext(req);
  const events = context.db.groupEvents.filter((candidate) => context.groupIds.has(candidate.groupId));
  const left = events.find((candidate) => candidate.id === parsed.data.leftEventId);
  const right = events.find((candidate) => candidate.id === parsed.data.rightEventId);
  if (!left || !right) {
    res.status(404).json({ error: "Conflict events not found for current user scope" });
    return;
  }

  if (parsed.data.action === "accept") {
    logConflictAuditEntry(context.db, context.userId, left.groupId, "conflict_acknowledged", left.id, right.id, {
      acknowledgedAt: new Date().toISOString()
    });
    await store.write(context.db);
    res.json({
      ok: true,
      action: "accept",
      acknowledged: true,
      leftEventId: left.id,
      rightEventId: right.id,
      groupId: left.groupId
    });
    return;
  }

  const targetId = parsed.data.preferredEventId ?? left.id;
  const target = events.find((candidate) => candidate.id === targetId) ?? left;
  const suggestionStart = suggestedStartISO(target, events);
  if (!suggestionStart) {
    res.status(409).json({ error: "No suitable conflict-free slot found" });
    return;
  }

  const targetWindow = parseEventWindow(target);
  if (!targetWindow) {
    res.status(400).json({ error: "Target event has invalid schedule payload" });
    return;
  }
  const duration = targetWindow.endDate - targetWindow.startDate;
  const suggestionEnd = new Date(Date.parse(suggestionStart) + duration).toISOString();

  if (parsed.data.action === "suggest") {
    logConflictAuditEntry(context.db, context.userId, target.groupId, "conflict_suggested", left.id, right.id, {
      targetEventId: target.id,
      suggestionStart,
      suggestionEnd
    });
    await store.write(context.db);
    res.json({
      ok: true,
      action: "suggest",
      suggestionStart,
      suggestionEnd,
      resolvedEventId: target.id,
      eventTitle: eventTitle(target),
      groupId: target.groupId
    });
    return;
  }

  const targetIndex = context.db.groupEvents.findIndex((candidate) => candidate.id === target.id);
  if (targetIndex < 0) {
    res.status(404).json({ error: "Target event not found" });
    return;
  }

  const currentTarget = context.db.groupEvents[targetIndex];
  if (!currentTarget) {
    res.status(404).json({ error: "Target event unavailable" });
    return;
  }
  const currentWindow = parseEventWindow(currentTarget);
  if (!currentWindow) {
    res.status(400).json({ error: "Target event has invalid schedule payload" });
    return;
  }

  const nextEnd = new Date(Date.parse(suggestionStart) + (currentWindow.endDate - currentWindow.startDate)).toISOString();
  const beforeStart = new Date(currentWindow.startDate).toISOString();
  const beforeEnd = new Date(currentWindow.endDate).toISOString();
  currentTarget.payload = {
    ...currentTarget.payload,
    startDate: suggestionStart,
    endDate: nextEnd
  };
  currentTarget.updatedAt = new Date().toISOString();

  const remainingConflicts = conflictsWithAny(currentTarget, events).length;
  logConflictAuditEntry(context.db, context.userId, currentTarget.groupId, "conflict_fixed", left.id, right.id, {
    targetEventId: currentTarget.id,
    beforeStart,
    beforeEnd,
    afterStart: suggestionStart,
    afterEnd: nextEnd,
    remainingConflicts
  });
  await store.write(context.db);

  res.json({
    ok: true,
    action: "fix",
    suggestionStart,
    suggestionEnd: nextEnd,
    resolvedEventId: currentTarget.id,
    eventTitle: eventTitle(currentTarget),
    groupId: currentTarget.groupId,
    beforeStart,
    beforeEnd,
    afterStart: suggestionStart,
    afterEnd: nextEnd,
    remainingConflicts,
    updatedEvent: currentTarget
  });
});

app.get("/groups/:groupId/conflicts/history", requireAuth, async (req: AuthRequest, res) => {
  const context = await getGroupMemberContext(req, res, ["Owner", "Admin"]);
  if (!context) {
    return;
  }

  const entries = context.db.audits
    .filter((entry) => entry.householdId === context.group.id && entry.action.startsWith("conflict_"))
    .sort((left, right) => right.createdAt.localeCompare(left.createdAt))
    .slice(0, 100)
    .map((entry) => ({
      id: entry.id,
      action: entry.action,
      actorUserId: entry.actorUserId,
      createdAt: entry.createdAt,
      details: entry.details ?? ""
    }));

  res.json({ groupId: context.group.id, entries });
});

app.patch("/me/profile", requireAuth, async (req: AuthRequest, res) => {
  const parsed = updateProfileSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const db = await store.read();
  const user = db.users.find((candidate) => candidate.id === req.userId);
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }

  user.displayName = parsed.data.displayName.trim();
  await store.write(db);
  res.json({ user: { id: user.id, email: user.email, displayName: user.displayName } });
});

app.patch("/me/password", requireAuth, async (req: AuthRequest, res) => {
  const parsed = changePasswordSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const db = await store.read();
  const user = db.users.find((candidate) => candidate.id === req.userId);
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }

  const matches = await bcrypt.compare(parsed.data.currentPassword, user.passwordHash);
  if (!matches) {
    res.status(401).json({ error: "Current password is incorrect" });
    return;
  }

  user.passwordHash = await bcrypt.hash(parsed.data.newPassword, 10);
  await store.write(db);
  res.json({ ok: true });
});

app.post("/households", requireAuth, async (req: AuthRequest, res) => {
  const parsed = householdSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const db = await store.read();
  const userId = req.userId!;
  if (db.memberships.some((m) => m.userId === userId)) {
    res.status(409).json({ error: "User already belongs to a household" });
    return;
  }

  const householdId = uuidv4();
  const code = randomHouseholdCode();
  db.households.push({
    id: householdId,
    name: parsed.data.name,
    code,
    createdBy: userId,
    createdAt: new Date().toISOString()
  });
  const membership: Membership = {
    userId,
    householdId,
    role: "Owner",
    joinedAt: new Date().toISOString()
  };
  db.memberships.push(membership);
  logAuditEntry(db, userId, householdId, "household_created", { details: parsed.data.name });
  await store.write(db);
  res.status(201).json({ householdId, code, membership });
});

app.post("/households/join", requireAuth, async (req: AuthRequest, res) => {
  const parsed = joinSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const db = await store.read();
  const userId = req.userId!;
  if (db.memberships.some((m) => m.userId === userId)) {
    res.status(409).json({ error: "User already belongs to a household" });
    return;
  }

  const household = db.households.find((candidate) => candidate.code === parsed.data.code.toUpperCase());
  if (!household) {
    res.status(404).json({ error: "Household not found" });
    return;
  }

  const user = db.users.find((candidate) => candidate.id === userId);
  const role = user && isConfiguredAdminEmail(user.email) ? "Owner" : "Member";

  const membership: Membership = {
    userId,
    householdId: household.id,
    role,
    joinedAt: new Date().toISOString()
  };
  db.memberships.push(membership);
  logAuditEntry(db, userId, household.id, "member_joined", { targetUserId: userId, details: role });
  await store.write(db);
  res.json({ household, membership });
});

app.get("/groups", requireAuth, async (req: AuthRequest, res) => {
  const db = await readDbWithGroupBridge();
  const userId = req.userId!;
  const memberships = db.groupMemberships.filter((membership) => membership.userId === userId);
  const groups = memberships
    .map((membership) => {
      const group = db.groups.find((candidate) => candidate.id === membership.groupId);
      if (!group) {
        return null;
      }
      return { group, membership };
    })
    .filter((record): record is { group: GroupWorkspace; membership: GroupMembership } => record !== null)
    .sort((left, right) => right.group.createdAt.localeCompare(left.group.createdAt));

  res.json({ groups });
});

app.post("/groups", requireAuth, async (req: AuthRequest, res) => {
  const parsed = groupSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const db = await readDbWithGroupBridge();
  const userId = req.userId!;
  const payloadType = parsed.data.type as GroupType;
  const groupId = uuidv4();
  const code = randomHouseholdCode();
  const now = new Date().toISOString();

  const group: GroupWorkspace = {
    id: groupId,
    name: parsed.data.name,
    type: payloadType,
    code,
    createdBy: userId,
    createdAt: now
  };

  const membership: GroupMembership = {
    userId,
    groupId,
    role: "Owner",
    joinedAt: now
  };

  db.groups.push(group);
  db.groupMemberships.push(membership);

  const hasLegacyMembership = db.memberships.some((candidate) => candidate.userId === userId);
  if (!hasLegacyMembership) {
    db.households.push({
      id: groupId,
      name: group.name,
      code,
      createdBy: userId,
      createdAt: now
    });
    db.memberships.push({
      userId,
      householdId: groupId,
      role: "Owner",
      joinedAt: now
    });
    logAuditEntry(db, userId, groupId, "household_created", { details: group.name });
  }

  await store.write(db);
  res.status(201).json({ group, membership });
});

app.post("/groups/join", requireAuth, async (req: AuthRequest, res) => {
  const parsed = joinSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const db = await readDbWithGroupBridge();
  const userId = req.userId!;
  const code = parsed.data.code.trim().toUpperCase();
  const group = db.groups.find((candidate) => candidate.code === code);
  if (!group) {
    res.status(404).json({ error: "Group not found" });
    return;
  }

  const existingMembership = db.groupMemberships.find(
    (candidate) => candidate.userId === userId && candidate.groupId === group.id
  );
  if (existingMembership) {
    res.status(409).json({ error: "User already belongs to this group" });
    return;
  }

  const user = db.users.find((candidate) => candidate.id === userId);
  const role: GroupRole = user && isConfiguredAdminEmail(user.email) ? "Owner" : "Member";
  const membership: GroupMembership = {
    userId,
    groupId: group.id,
    role,
    joinedAt: new Date().toISOString()
  };
  db.groupMemberships.push(membership);

  const householdId = group.legacyHouseholdId ?? group.id;
  const hasLegacyMembership = db.memberships.some((candidate) => candidate.userId === userId);
  const legacyHouseholdExists = db.households.some((candidate) => candidate.id === householdId);
  if (!hasLegacyMembership && legacyHouseholdExists) {
    db.memberships.push({
      userId,
      householdId,
      role: role === "Owner" ? "Owner" : "Member",
      joinedAt: membership.joinedAt
    });
  }

  await store.write(db);
  res.json({ group, membership });
});

app.get("/groups/:groupId", requireAuth, async (req: AuthRequest, res) => {
  const context = await getGroupMemberContext(req, res);
  if (!context) {
    return;
  }

  res.json({ group: context.group, membership: context.membership });
});

app.get("/groups/:groupId/members", requireAuth, async (req: AuthRequest, res) => {
  const context = await getGroupMemberContext(req, res);
  if (!context) {
    return;
  }

  const members = context.db.groupMemberships
    .filter((candidate) => candidate.groupId === context.group.id)
    .map((candidate) => ({
      membership: candidate,
      user: context.db.users.find((user) => user.id === candidate.userId) ?? null
    }))
    .sort((left, right) => {
      if (left.membership.role === right.membership.role) {
        return left.membership.joinedAt.localeCompare(right.membership.joinedAt);
      }
      return left.membership.role === "Owner" ? -1 : 1;
    });

  res.json({ group: context.group, currentUserId: context.userId, members });
});

app.patch("/groups/:groupId/members/:userId/role", requireAuth, async (req: AuthRequest, res) => {
  const parsed = adminRoleSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const context = await getGroupMemberContext(req, res, ["Owner", "Admin"]);
  if (!context) {
    return;
  }

  const targetUserParam = req.params.userId;
  const targetUserId = Array.isArray(targetUserParam) ? targetUserParam[0] : targetUserParam;
  if (!targetUserId) {
    res.status(400).json({ error: "Missing user id" });
    return;
  }

  const targetMembership = context.db.groupMemberships.find(
    (candidate) => candidate.groupId === context.group.id && candidate.userId === targetUserId
  );
  if (!targetMembership) {
    res.status(404).json({ error: "Membership not found" });
    return;
  }

  const nextRole = parsed.data.role;
  if (targetUserId === context.userId && nextRole !== "Owner") {
    res.status(400).json({ error: "You cannot demote yourself." });
    return;
  }

  if (targetMembership.role === nextRole) {
    res.json({ membership: targetMembership });
    return;
  }

  if (targetMembership.role === "Owner" && nextRole !== "Owner") {
    const ownerCount = context.db.groupMemberships.filter(
      (candidate) => candidate.groupId === context.group.id && candidate.role === "Owner"
    ).length;
    if (ownerCount <= 1) {
      res.status(400).json({ error: "A group must have at least one owner." });
      return;
    }
  }

  if (context.membership.role !== "Owner" && (nextRole === "Owner" || targetMembership.role === "Owner")) {
    res.status(403).json({ error: "Only owners can change owner roles." });
    return;
  }

  targetMembership.role = nextRole;
  await store.write(context.db);
  res.json({ membership: targetMembership });
});

app.get("/groups/:groupId/events", requireAuth, async (req: AuthRequest, res) => {
  const context = await getGroupMemberContext(req, res);
  if (!context) {
    return;
  }
  const events = context.db.groupEvents.filter((candidate) => candidate.groupId === context.group.id);
  res.json({ events });
});

app.post("/groups/:groupId/events", requireAuth, async (req: AuthRequest, res) => {
  const parsed = groupPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  const context = await getGroupMemberContext(req, res, ["Owner", "Admin", "Member"]);
  if (!context) {
    return;
  }

  const record: GroupEventRecord = {
    id: uuidv4(),
    groupId: context.group.id,
    createdBy: context.userId,
    updatedAt: new Date().toISOString(),
    payload: parsed.data.payload
  };
  context.db.groupEvents.push(record);
  await store.write(context.db);
  res.status(201).json({ event: record });
});

app.get("/groups/:groupId/lists", requireAuth, async (req: AuthRequest, res) => {
  const context = await getGroupMemberContext(req, res);
  if (!context) {
    return;
  }
  const lists = context.db.groupLists.filter((candidate) => candidate.groupId === context.group.id);
  res.json({ lists });
});

app.post("/groups/:groupId/lists", requireAuth, async (req: AuthRequest, res) => {
  const parsed = groupPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  const context = await getGroupMemberContext(req, res, ["Owner", "Admin", "Member"]);
  if (!context) {
    return;
  }

  const record: GroupListRecord = {
    id: uuidv4(),
    groupId: context.group.id,
    createdBy: context.userId,
    updatedAt: new Date().toISOString(),
    payload: parsed.data.payload
  };
  context.db.groupLists.push(record);
  await store.write(context.db);
  res.status(201).json({ list: record });
});

app.get("/groups/:groupId/plans", requireAuth, async (req: AuthRequest, res) => {
  const context = await getGroupMemberContext(req, res);
  if (!context) {
    return;
  }
  const plans = context.db.groupPlans.filter((candidate) => candidate.groupId === context.group.id);
  res.json({ plans });
});

app.post("/groups/:groupId/plans", requireAuth, async (req: AuthRequest, res) => {
  const parsed = groupPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  const context = await getGroupMemberContext(req, res, ["Owner", "Admin", "Member"]);
  if (!context) {
    return;
  }

  const record: GroupPlanRecord = {
    id: uuidv4(),
    groupId: context.group.id,
    createdBy: context.userId,
    updatedAt: new Date().toISOString(),
    payload: parsed.data.payload
  };
  context.db.groupPlans.push(record);
  await store.write(context.db);
  res.status(201).json({ plan: record });
});

app.get("/groups/:groupId/routines", requireAuth, async (req: AuthRequest, res) => {
  const context = await getGroupMemberContext(req, res);
  if (!context) {
    return;
  }
  const routines = context.db.groupRoutines.filter((candidate) => candidate.groupId === context.group.id);
  res.json({ routines });
});

app.post("/groups/:groupId/routines", requireAuth, async (req: AuthRequest, res) => {
  const parsed = groupPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  const context = await getGroupMemberContext(req, res, ["Owner", "Admin", "Member"]);
  if (!context) {
    return;
  }

  const record: GroupRoutineRecord = {
    id: uuidv4(),
    groupId: context.group.id,
    createdBy: context.userId,
    updatedAt: new Date().toISOString(),
    payload: parsed.data.payload
  };
  context.db.groupRoutines.push(record);
  await store.write(context.db);
  res.status(201).json({ routine: record });
});

app.get("/admin/household/members", requireAuth, async (req: AuthRequest, res) => {
  const context = await getOwnerContext(req, res);
  if (!context) {
    return;
  }

  const members = context.db.memberships
    .filter((candidate) => candidate.householdId === context.household.id)
    .map((candidate) => ({
      membership: candidate,
      user: context.db.users.find((user) => user.id === candidate.userId) ?? null
    }))
    .sort((left, right) => {
      if (left.membership.role === right.membership.role) {
        return left.membership.joinedAt.localeCompare(right.membership.joinedAt);
      }
      return left.membership.role === "Owner" ? -1 : 1;
    });

  await store.write(context.db);
  res.json({ household: context.household, currentUserId: context.userId, members });
});

app.patch("/admin/household/members/:userId/role", requireAuth, async (req: AuthRequest, res) => {
  const parsed = adminRoleSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const context = await getOwnerContext(req, res);
  if (!context) {
    return;
  }

  const targetUserParam = req.params.userId;
  const targetUserId = Array.isArray(targetUserParam) ? targetUserParam[0] : targetUserParam;
  if (!targetUserId) {
    res.status(400).json({ error: "Missing user id" });
    return;
  }
  const targetMembership = context.db.memberships.find(
    (candidate) => candidate.userId === targetUserId && candidate.householdId === context.household.id
  );
  if (!targetMembership) {
    res.status(404).json({ error: "Membership not found" });
    return;
  }

  if (targetUserId === context.userId && parsed.data.role !== "Owner") {
    res.status(400).json({ error: "You cannot demote yourself." });
    return;
  }

  if (targetMembership.role === parsed.data.role) {
    await store.write(context.db);
    res.json({ membership: targetMembership });
    return;
  }

  if (targetMembership.role === "Owner" && parsed.data.role === "Member") {
    const ownerCount = context.db.memberships.filter(
      (candidate) => candidate.householdId === context.household.id && candidate.role === "Owner"
    ).length;
    if (ownerCount <= 1) {
      res.status(400).json({ error: "A household must have at least one owner." });
      return;
    }
  }

  targetMembership.role = parsed.data.role;
  logAuditEntry(context.db, context.userId, context.household.id, "member_role_changed", {
    targetUserId,
    details: parsed.data.role
  });
  await store.write(context.db);
  res.json({ membership: targetMembership });
});

app.delete("/admin/household/members/:userId", requireAuth, async (req: AuthRequest, res) => {
  const context = await getOwnerContext(req, res);
  if (!context) {
    return;
  }

  const targetUserParam = req.params.userId;
  const targetUserId = Array.isArray(targetUserParam) ? targetUserParam[0] : targetUserParam;
  if (!targetUserId) {
    res.status(400).json({ error: "Missing user id" });
    return;
  }
  const targetMembershipIndex = context.db.memberships.findIndex(
    (candidate) => candidate.userId === targetUserId && candidate.householdId === context.household.id
  );
  if (targetMembershipIndex < 0) {
    res.status(404).json({ error: "Membership not found" });
    return;
  }

  if (targetUserId === context.userId) {
    res.status(400).json({ error: "Owners cannot remove themselves." });
    return;
  }

  const targetMembership = context.db.memberships[targetMembershipIndex];
  if (targetMembership.role === "Owner") {
    const ownerCount = context.db.memberships.filter(
      (candidate) => candidate.householdId === context.household.id && candidate.role === "Owner"
    ).length;
    if (ownerCount <= 1) {
      res.status(400).json({ error: "A household must have at least one owner." });
      return;
    }
  }

  context.db.memberships.splice(targetMembershipIndex, 1);
  logAuditEntry(context.db, context.userId, context.household.id, "member_removed", {
    targetUserId
  });
  await store.write(context.db);
  res.json({ ok: true });
});

app.post("/admin/household/transfer-owner", requireAuth, async (req: AuthRequest, res) => {
  const parsed = transferOwnerSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const context = await getOwnerContext(req, res);
  if (!context) {
    return;
  }

  if (parsed.data.userId === context.userId) {
    res.status(400).json({ error: "You already own this household." });
    return;
  }

  const targetMembership = context.db.memberships.find(
    (candidate) => candidate.userId === parsed.data.userId && candidate.householdId === context.household.id
  );
  if (!targetMembership) {
    res.status(404).json({ error: "Target member not found" });
    return;
  }

  targetMembership.role = "Owner";
  const requesterUser = context.db.users.find((candidate) => candidate.id === context.userId);
  if (!requesterUser || !isConfiguredAdminEmail(requesterUser.email)) {
    context.membership.role = "Member";
  }

  logAuditEntry(context.db, context.userId, context.household.id, "owner_transferred", {
    targetUserId: parsed.data.userId
  });
  await store.write(context.db);
  res.json({ membership: targetMembership });
});

app.post("/admin/household/regenerate-code", requireAuth, async (req: AuthRequest, res) => {
  const context = await getOwnerContext(req, res);
  if (!context) {
    return;
  }

  context.household.code = randomHouseholdCode();
  logAuditEntry(context.db, context.userId, context.household.id, "join_code_regenerated", {
    details: context.household.code
  });
  await store.write(context.db);
  res.json({ household: context.household });
});

app.get("/admin/household/audit", requireAuth, async (req: AuthRequest, res) => {
  const context = await getOwnerContext(req, res);
  if (!context) {
    return;
  }

  const entries = context.db.audits
    .filter((entry) => entry.householdId === context.household.id)
    .sort((left, right) => right.createdAt.localeCompare(left.createdAt))
    .slice(0, 100);

  await store.write(context.db);
  res.json({ entries });
});

app.get("/households/current", requireAuth, async (req: AuthRequest, res) => {
  const db = await store.read();
  let dbUpdated = enforceAdminOwnerMembership(db, req.userId!);
  const membership = db.memberships.find((m) => m.userId === req.userId);
  if (!membership) {
    res.status(404).json({ error: "No household membership" });
    return;
  }

  if (dbUpdated) {
    await store.write(db);
  }

  const household = db.households.find((candidate) => candidate.id === membership.householdId);
  res.json({ household, membership });
});

app.get("/sync/snapshot", requireAuth, async (req: AuthRequest, res) => {
  const db = await store.read();
  if (enforceAdminOwnerMembership(db, req.userId!)) {
    await store.write(db);
  }
  const membership = db.memberships.find((candidate) => candidate.userId === req.userId) ?? null;
  if (!membership) {
    res.status(404).json({ error: "No household membership" });
    return;
  }
  const snapshot = db.snapshots.find((candidate) => candidate.householdId === membership.householdId) ?? null;
  res.json({ snapshot });
});

app.put("/sync/snapshot", requireAuth, async (req: AuthRequest, res) => {
  const parsed = snapshotSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  const db = await store.read();
  if (enforceAdminOwnerMembership(db, req.userId!)) {
    await store.write(db);
  }
  const membership = db.memberships.find((m) => m.userId === req.userId);
  if (!membership) {
    res.status(404).json({ error: "No household membership" });
    return;
  }
  const user = db.users.find((candidate) => candidate.id === req.userId);
  const snapshot: HouseholdSnapshot = {
    householdId: membership.householdId,
    updatedAt: new Date().toISOString(),
    updatedBy: user?.displayName ?? "Unknown",
    payload: parsed.data.payload
  };

  const index = db.snapshots.findIndex((candidate) => candidate.householdId === membership.householdId);
  if (index >= 0) {
    db.snapshots[index] = snapshot;
  } else {
    db.snapshots.push(snapshot);
  }

  await store.write(db);
  res.json({ snapshot });
});

app.get(/^\/(?!auth|admin|sync|households|groups|me|conflicts|health).*/, (_req, res) => {
  res.sendFile(path.join(webRoot, "index.html"));
});

app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  if (err instanceof Error && err.message.includes("CORS")) {
    res.status(403).json({ error: "Origin is not allowed." });
    return;
  }
  console.error("Unhandled server error", err);
  res.status(500).json({ error: "Internal server error" });
});

app.listen(port, () => {
  console.log(`Aura backend listening on :${port}`);
});