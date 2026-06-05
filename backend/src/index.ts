import "dotenv/config";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { v4 as uuidv4 } from "uuid";
import { z } from "zod";
import { JsonStore } from "./store.js";
import type { DatabaseShape, HouseholdAuditEntry, HouseholdSnapshot, Membership, User } from "./types.js";

const app = express();
const port = Number(process.env.PORT ?? 4000);
const jwtSecret = process.env.JWT_SECRET ?? "";
const jwtIssuer = process.env.JWT_ISSUER ?? "aura-family-backend";
const jwtAudience = process.env.JWT_AUDIENCE ?? "aura-family-clients";
const dataFile = process.env.DATA_FILE ?? "./data/db.json";
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
const store = new JsonStore(dataFile);

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
app.use(["/sync", "/households", "/me"], writeLimiter);

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

const joinSchema = z.object({
  code: z.string().min(4)
});

const snapshotSchema = z.object({
  payload: z.record(z.unknown())
});

const updateProfileSchema = z.object({
  displayName: z.string().min(1)
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8)
});

const adminRoleSchema = z.object({
  role: z.enum(["Owner", "Member"])
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