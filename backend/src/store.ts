import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import type { DatabaseShape } from "./types.js";

const fallbackDb: DatabaseShape = {
  users: [],
  memberships: [],
  households: [],
  snapshots: [],
  audits: []
};

export class JsonStore {
  constructor(private readonly filePath: string) {}

  private async ensureFile() {
    const abs = resolve(this.filePath);
    await mkdir(dirname(abs), { recursive: true });
    try {
      await readFile(abs, "utf8");
    } catch {
      await writeFile(abs, JSON.stringify(fallbackDb, null, 2), "utf8");
    }
    return abs;
  }

  async read(): Promise<DatabaseShape> {
    const abs = await this.ensureFile();
    const raw = await readFile(abs, "utf8");
    const parsed = JSON.parse(raw) as Partial<DatabaseShape>;
    return {
      users: parsed.users ?? [],
      memberships: parsed.memberships ?? [],
      households: parsed.households ?? [],
      snapshots: parsed.snapshots ?? [],
      audits: parsed.audits ?? []
    };
  }

  async write(next: DatabaseShape) {
    const abs = await this.ensureFile();
    await writeFile(abs, JSON.stringify(next, null, 2), "utf8");
  }

  async update(mutator: (db: DatabaseShape) => void | DatabaseShape) {
    const db = await this.read();
    const maybe = mutator(db);
    await this.write((maybe ?? db) as DatabaseShape);
  }
}