import "dotenv/config";
import express from "express";
import cors from "cors";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { v4 as uuidv4 } from "uuid";
import { z } from "zod";
import { JsonStore } from "./store.js";
import type { HouseholdSnapshot, Membership, User } from "./types.js";

const app = express();
const port = Number(process.env.PORT ?? 4000);
const jwtSecret = process.env.JWT_SECRET ?? "change-me";
const dataFile = process.env.DATA_FILE ?? "./data/db.json";
const store = new JsonStore(dataFile);

app.use(cors());
app.use(express.json({ limit: "2mb" }));

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

type AuthRequest = express.Request & { userId?: string };

function signToken(userId: string) {
  return jwt.sign({ sub: userId }, jwtSecret, { expiresIn: "30d" });
}

function requireAuth(req: AuthRequest, res: express.Response, next: express.NextFunction) {
  const auth = req.header("authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) {
    res.status(401).json({ error: "Missing token" });
    return;
  }
  try {
    const decoded = jwt.verify(token, jwtSecret) as { sub: string };
    req.userId = decoded.sub;
    next();
  } catch {
    res.status(401).json({ error: "Invalid token" });
  }
}

async function getCurrentMembership(userId: string) {
  const db = await store.read();
  return db.memberships.find((m) => m.userId === userId) ?? null;
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
  if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
    res.status(401).json({ error: "Invalid credentials" });
    return;
  }

  res.json({ token: signToken(user.id), user: { id: user.id, email: user.email, displayName: user.displayName } });
});

app.get("/me", requireAuth, async (req: AuthRequest, res) => {
  const db = await store.read();
  const user = db.users.find((candidate) => candidate.id === req.userId);
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }

  const membership = db.memberships.find((m) => m.userId === user.id) ?? null;
  res.json({
    user: { id: user.id, email: user.email, displayName: user.displayName },
    membership
  });
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
  const code = Math.random().toString(36).slice(2, 8).toUpperCase();
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

  const membership: Membership = {
    userId,
    householdId: household.id,
    role: "Member",
    joinedAt: new Date().toISOString()
  };
  db.memberships.push(membership);
  await store.write(db);
  res.json({ household, membership });
});

app.get("/households/current", requireAuth, async (req: AuthRequest, res) => {
  const db = await store.read();
  const membership = db.memberships.find((m) => m.userId === req.userId);
  if (!membership) {
    res.status(404).json({ error: "No household membership" });
    return;
  }

  const household = db.households.find((candidate) => candidate.id === membership.householdId);
  res.json({ household, membership });
});

app.get("/sync/snapshot", requireAuth, async (req: AuthRequest, res) => {
  const membership = await getCurrentMembership(req.userId!);
  if (!membership) {
    res.status(404).json({ error: "No household membership" });
    return;
  }
  const db = await store.read();
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

app.listen(port, () => {
  console.log(`Aura backend listening on :${port}`);
});