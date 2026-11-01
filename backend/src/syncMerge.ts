// Server-side merge for the per-group sync snapshot.
//
// The iOS app uploads its whole local copy of a group's data. Storing that
// verbatim (the old behaviour) meant every upload replaced everyone else's
// work: a member whose phone hadn't seen a new event yet would erase it, a
// deletion was indistinguishable from "never had it", and any member could
// rewrite or delete anyone's event. Instead each upload is merged into the
// stored copy record by record:
//
// - Records are matched by `id`; the newer `modifiedAt` wins.
// - Events, lists, plans and stores belong to their creator
//   (`createdByUserId`, falling back to `ownerName` for records written before
//   that field existed). Only the creator's uploads may change them; only the
//   creator or the group Owner may delete them.
// - Anyone may add an item to a shared list/plan, and tick it done/bought;
//   changing an item's details is the item creator's alone.
// - Deletions travel as tombstones (`deletedIds`: id -> deletion time), so a
//   record missing from an upload is kept rather than treated as deleted.
// - Everyone else's edits go through `proposals`, which only the target's
//   creator can approve or decline.
//
// Dates inside the payload are the app's JSONEncoder default: seconds since
// 2001-01-01 (Apple's reference date), as numbers.

export type Rec = Record<string, unknown>;
export type Payload = Rec;

export interface Actor {
  userId: string;
  displayName: string;
  isOwner: boolean;
}

const APPLE_EPOCH_OFFSET_SECONDS = 978_307_200;
const TOMBSTONE_TTL_SECONDS = 90 * 24 * 3600;
const RESOLVED_PROPOSAL_TTL_SECONDS = 30 * 24 * 3600;

const FREE_ITEM_FIELDS = ["isDone", "completedByName", "boughtAt"] as const;

export function appleNow(): number {
  return Date.now() / 1000 - APPLE_EPOCH_OFFSET_SECONDS;
}

export function appleSecondsToISO(value: unknown): string | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  return new Date((value + APPLE_EPOCH_OFFSET_SECONDS) * 1000).toISOString();
}

function records(value: unknown): Rec[] {
  return Array.isArray(value)
    ? value.filter((entry): entry is Rec => typeof entry === "object" && entry !== null && typeof (entry as Rec).id === "string")
    : [];
}

function tombstones(value: unknown): Record<string, number> {
  const result: Record<string, number> = {};
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return result;
  }
  for (const [id, at] of Object.entries(value as Rec)) {
    if (typeof at === "number" && Number.isFinite(at)) {
      result[id] = at;
    }
  }
  return result;
}

function modifiedAt(record: Rec): number {
  return typeof record.modifiedAt === "number" ? record.modifiedAt : 0;
}

function sameName(left: unknown, right: string) {
  return typeof left === "string" && left.trim().toLowerCase() === right.trim().toLowerCase();
}

/// Lists and activities were historically written under their old "family*"
/// keys; read either, write the key the app writes.
function listsOf(payload: Payload) {
  return records(payload.familyLists ?? payload.groupLists);
}

function activitiesOf(payload: Payload) {
  return records(payload.familyActivities ?? payload.groupActivities);
}

export function isCreator(actor: { userId: string; displayName: string }, record: Rec): boolean {
  if (typeof record.createdByUserId === "string" && record.createdByUserId.length > 0) {
    return record.createdByUserId === actor.userId;
  }
  // Written before records carried a creator id: the display name is the
  // only ownership signal there is. An unowned legacy record stays editable
  // by anyone, as it always was.
  const ownerName = typeof record.ownerName === "string" ? record.ownerName.trim() : "";
  return ownerName.length === 0 || sameName(ownerName, actor.displayName);
}

function canDelete(actor: Actor, record: Rec): boolean {
  return actor.isOwner || isCreator(actor, record);
}

/// Items (in lists and plans) have no ownerName; a legacy item with no
/// creator id belongs to whoever owns its parent.
function itemOwner(item: Rec, parent: Rec): Rec {
  return typeof item.createdByUserId === "string" && item.createdByUserId.length > 0 ? item : parent;
}

function newer(stored: Rec, incoming: Rec): Rec {
  // Ties (including two legacy records with no modifiedAt) go to the upload,
  // which was the only behaviour before modifiedAt existed.
  return modifiedAt(incoming) >= modifiedAt(stored) ? incoming : stored;
}

function mergeItems(
  storedItems: Rec[],
  incomingItems: Rec[],
  parent: Rec,
  actor: Actor,
  deleted: Record<string, number>
): Rec[] {
  const byId = new Map(storedItems.map((item) => [item.id as string, item]));
  for (const incoming of incomingItems) {
    const id = incoming.id as string;
    if (deleted[id] !== undefined) {
      continue;
    }
    const stored = byId.get(id);
    if (!stored) {
      byId.set(id, incoming);
      continue;
    }
    if (isCreator(actor, itemOwner(stored, parent))) {
      byId.set(id, newer(stored, incoming));
      continue;
    }
    // Not this member's item: only the tick/bought fields may change.
    if (modifiedAt(incoming) >= modifiedAt(stored)) {
      const next: Rec = { ...stored, modifiedAt: Math.max(modifiedAt(incoming), modifiedAt(stored)) };
      for (const field of FREE_ITEM_FIELDS) {
        if (field in incoming) {
          next[field] = incoming[field];
        } else {
          delete next[field];
        }
      }
      byId.set(id, next);
    }
  }
  return [...byId.values()].filter((item) => deleted[item.id as string] === undefined);
}

function mergeCollection(
  stored: Rec[],
  incoming: Rec[],
  actor: Actor,
  deleted: Record<string, number>,
  options: { owned: boolean; hasItems: boolean }
): Rec[] {
  const byId = new Map(stored.map((record) => [record.id as string, record]));
  for (const record of incoming) {
    const id = record.id as string;
    if (deleted[id] !== undefined) {
      continue;
    }
    const existing = byId.get(id);
    if (!existing) {
      byId.set(id, record);
      continue;
    }
    const mayEdit = !options.owned || isCreator(actor, existing);
    const base = mayEdit ? newer(existing, record) : existing;
    if (options.hasItems) {
      byId.set(id, {
        ...base,
        items: mergeItems(records(existing.items), records(record.items), existing, actor, deleted)
      });
    } else {
      byId.set(id, base);
    }
  }
  return [...byId.values()].filter((record) => deleted[record.id as string] === undefined);
}

/// Finds whatever an id refers to (top-level record, or an item inside a list
/// or plan) so a deletion can be checked against its owner.
function findDeletable(payload: Payload, id: string): { record: Rec; owner: Rec; owned: boolean } | null {
  for (const key of ["events", "groupPlans", "stores"] as const) {
    const match = records(payload[key]).find((record) => record.id === id);
    if (match) {
      return { record: match, owner: match, owned: true };
    }
  }
  for (const parent of [...listsOf(payload), ...records(payload.groupPlans)]) {
    if (parent.id === id) {
      return { record: parent, owner: parent, owned: true };
    }
    const item = records(parent.items).find((candidate) => candidate.id === id);
    if (item) {
      return { record: item, owner: itemOwner(item, parent), owned: true };
    }
  }
  return null;
}

function mergeTombstones(stored: Payload, incoming: Payload, actor: Actor) {
  const merged = tombstones(stored.deletedIds);
  const rejected: string[] = [];
  for (const [id, at] of Object.entries(tombstones(incoming.deletedIds))) {
    if (merged[id] !== undefined) {
      continue;
    }
    const target = findDeletable(stored, id);
    if (target && target.owned && !canDelete(actor, target.owner)) {
      rejected.push(id);
      continue;
    }
    merged[id] = at;
  }
  const cutoff = appleNow() - TOMBSTONE_TTL_SECONDS;
  for (const [id, at] of Object.entries(merged)) {
    if (at < cutoff) {
      delete merged[id];
    }
  }
  return { merged, rejected };
}

function targetOfProposal(payload: Payload, proposal: Rec): Rec | null {
  const targetId = proposal.targetId;
  if (typeof targetId !== "string") {
    return null;
  }
  return findDeletable(payload, targetId)?.owner ?? null;
}

function mergeProposals(stored: Payload, incoming: Payload, merged: Payload, actor: Actor): Rec[] {
  const byId = new Map(records(stored.proposals).map((proposal) => [proposal.id as string, proposal]));
  for (const proposal of records(incoming.proposals)) {
    const id = proposal.id as string;
    const existing = byId.get(id);
    if (!existing) {
      // Nobody can file a proposal in someone else's name.
      if (proposal.proposerUserId === actor.userId && proposal.status === "pending") {
        // Stamp the real owner rather than trusting the uploader's claim.
        const target = targetOfProposal(merged, proposal);
        const ownerId = target && typeof target.createdByUserId === "string" ? target.createdByUserId : proposal.targetOwnerUserId;
        byId.set(id, { ...proposal, targetOwnerUserId: ownerId });
      }
      continue;
    }
    if (existing.status !== "pending" || proposal.status === existing.status) {
      continue;
    }
    const target = targetOfProposal(merged, existing) ?? targetOfProposal(stored, existing);
    const isTargetCreator =
      existing.targetOwnerUserId === actor.userId || (target !== null && isCreator(actor, target));
    const resolving = proposal.status === "approved" || proposal.status === "declined";
    const withdrawing = proposal.status === "withdrawn" && existing.proposerUserId === actor.userId;
    if ((resolving && isTargetCreator) || withdrawing) {
      byId.set(id, { ...existing, status: proposal.status, resolvedAt: proposal.resolvedAt ?? appleNow(), modifiedAt: appleNow() });
    }
  }
  const cutoff = appleNow() - RESOLVED_PROPOSAL_TTL_SECONDS;
  return [...byId.values()].filter((proposal) => {
    if (proposal.status === "pending") {
      return true;
    }
    const resolvedAt = typeof proposal.resolvedAt === "number" ? proposal.resolvedAt : 0;
    return resolvedAt >= cutoff;
  });
}

export function mergeSnapshotPayload(stored: Payload | null, incoming: Payload, actor: Actor): Payload {
  const base: Payload = stored ?? {};
  const { merged: deleted } = mergeTombstones(base, incoming, actor);

  const merged: Payload = {
    ...base,
    ...incoming,
    deletedIds: deleted,
    events: mergeCollection(records(base.events), records(incoming.events), actor, deleted, { owned: true, hasItems: false }),
    familyLists: mergeCollection(listsOf(base), listsOf(incoming), actor, deleted, { owned: true, hasItems: true }),
    groupPlans: mergeCollection(records(base.groupPlans), records(incoming.groupPlans), actor, deleted, { owned: true, hasItems: true }),
    stores: mergeCollection(records(base.stores), records(incoming.stores), actor, deleted, { owned: true, hasItems: false }),
    familyActivities: mergeCollection(activitiesOf(base), activitiesOf(incoming), actor, deleted, { owned: false, hasItems: false }),
    stepSnapshots: mergeCollection(records(base.stepSnapshots), records(incoming.stepSnapshots), actor, deleted, { owned: false, hasItems: false }),
    categories: mergeCollection(records(base.categories), records(incoming.categories), actor, deleted, { owned: false, hasItems: false }),
    members: mergeCollection(records(base.members), records(incoming.members), actor, deleted, { owned: false, hasItems: false })
  };
  delete merged.groupLists;
  delete merged.groupActivities;
  merged.proposals = mergeProposals(base, incoming, merged, actor);
  return merged;
}

/// Whether `viewer` may see a record with Personal/Custom visibility.
/// Visibility rules were previously enforced only by the app hiding records
/// it had already downloaded; filtering here keeps them off other members'
/// phones entirely.
export function canView(viewer: { userId: string; displayName: string }, record: Rec): boolean {
  const visibility = record.visibility;
  if (visibility !== "Personal" && visibility !== "Custom") {
    return true;
  }
  const mine =
    typeof record.createdByUserId === "string" && record.createdByUserId.length > 0
      ? record.createdByUserId === viewer.userId
      : sameName(record.ownerName, viewer.displayName);
  if (mine || visibility === "Personal") {
    return mine;
  }
  const sharedWith = Array.isArray(record.sharedWithNames) ? record.sharedWithNames : [];
  return sharedWith.some((name) => sameName(name, viewer.displayName));
}

export function filterPayloadForViewer(payload: Payload, viewer: { userId: string; displayName: string }): Payload {
  const visible = (list: Rec[]) => list.filter((record) => canView(viewer, record));
  return {
    ...payload,
    events: visible(records(payload.events)),
    familyLists: visible(listsOf(payload)),
    groupPlans: visible(records(payload.groupPlans)),
    familyActivities: visible(activitiesOf(payload)),
    stepSnapshots: visible(records(payload.stepSnapshots)),
    proposals: records(payload.proposals).filter(
      (proposal) =>
        proposal.proposerUserId === viewer.userId ||
        proposal.targetOwnerUserId === viewer.userId ||
        (typeof proposal.targetOwnerUserId !== "string" && sameName(proposal.targetOwnerName, viewer.displayName))
    )
  };
}

export function eventsOf(payload: Payload) {
  return records(payload.events);
}

export function listsOfPayload(payload: Payload) {
  return listsOf(payload);
}

export function plansOf(payload: Payload) {
  return records(payload.groupPlans);
}

export function proposalsOf(payload: Payload) {
  return records(payload.proposals);
}

export function itemsOf(record: Rec) {
  return records(record.items);
}
