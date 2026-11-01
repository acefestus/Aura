import { Pool } from "pg";
import type { DatabaseShape } from "./types.js";
import { type DataStore, fallbackDb, normalizeDb } from "./store.js";

const ROW_ID = "singleton";

export class PgStore implements DataStore {
  private readonly pool: Pool;
  private readonly ready: Promise<void>;
  // This server is the only writer of app_state and runs as a single
  // instance, so the last-written state can be served from memory instead
  // of transferring and re-parsing the whole database from Postgres on every
  // read -- which every app's 6-second sync poll triggers. Callers get a
  // clone: handlers mutate what read() returns before (or without) writing.
  private cache: DatabaseShape | null = null;

  constructor(connectionString: string) {
    this.pool = new Pool({
      connectionString,
      ssl: connectionString.includes("localhost") ? undefined : { rejectUnauthorized: false }
    });
    this.ready = this.init();
  }

  private async init() {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS app_state (
        id text PRIMARY KEY,
        data jsonb NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now()
      )
    `);
    await this.pool.query(
      `INSERT INTO app_state (id, data) VALUES ($1, $2::jsonb) ON CONFLICT (id) DO NOTHING`,
      [ROW_ID, JSON.stringify(fallbackDb)]
    );
  }

  async read(): Promise<DatabaseShape> {
    await this.ready;
    if (!this.cache) {
      const { rows } = await this.pool.query("SELECT data FROM app_state WHERE id = $1", [ROW_ID]);
      this.cache = normalizeDb((rows[0]?.data ?? {}) as Partial<DatabaseShape>);
    }
    return structuredClone(this.cache);
  }

  async write(next: DatabaseShape): Promise<void> {
    await this.ready;
    await this.pool.query(
      "UPDATE app_state SET data = $2::jsonb, updated_at = now() WHERE id = $1",
      [ROW_ID, JSON.stringify(next)]
    );
    this.cache = structuredClone(next);
  }

  async update(mutator: (db: DatabaseShape) => void | DatabaseShape): Promise<void> {
    await this.ready;
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const { rows } = await client.query("SELECT data FROM app_state WHERE id = $1 FOR UPDATE", [ROW_ID]);
      const db = normalizeDb((rows[0]?.data ?? {}) as Partial<DatabaseShape>);
      const maybe = mutator(db);
      const next = (maybe ?? db) as DatabaseShape;
      await client.query("UPDATE app_state SET data = $2::jsonb, updated_at = now() WHERE id = $1", [
        ROW_ID,
        JSON.stringify(next)
      ]);
      await client.query("COMMIT");
      this.cache = structuredClone(next);
    } catch (err) {
      await client.query("ROLLBACK");
      throw err;
    } finally {
      client.release();
    }
  }
}
