import "dotenv/config";
import { readFile } from "node:fs/promises";
import { normalizeDb } from "../store.js";
import { PgStore } from "../pgStore.js";

async function main() {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    throw new Error("DATABASE_URL must be set to migrate into Postgres.");
  }
  const dataFile = process.env.DATA_FILE ?? "./data/db.json";
  const raw = await readFile(dataFile, "utf8");
  const db = normalizeDb(JSON.parse(raw));

  const store = new PgStore(databaseUrl);
  await store.write(db);

  console.log(
    `Migrated ${db.users.length} users, ${db.groups.length} groups, ${db.households.length} households from ${dataFile} into Postgres.`
  );
  process.exit(0);
}

main().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
