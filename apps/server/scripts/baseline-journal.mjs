// One-off: emit __drizzle_migrations baseline rows that EXACTLY match the
// committed journal, using drizzle's own readMigrationFiles so the sha256
// hashes are identical to what `drizzle-kit migrate` computes at runtime.
//
// Output: SQL to STDOUT (hashes are not secrets). Review, then apply to the
// target DB inside a transaction. Safe: __drizzle_migrations is migrate-only
// metadata, never read by the running app.
import { readMigrationFiles } from 'drizzle-orm/migrator';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsFolder = resolve(here, '../src/db/migrations');

const migrations = readMigrationFiles({ migrationsFolder });

const values = migrations
  .map((m) => `  ('${m.hash}', ${m.folderMillis})`)
  .join(',\n');

console.log(`-- ${migrations.length} migrations from journal`);
console.log('BEGIN;');
console.log('TRUNCATE "drizzle"."__drizzle_migrations" RESTART IDENTITY;');
console.log('INSERT INTO "drizzle"."__drizzle_migrations" (hash, created_at) VALUES');
console.log(values + ';');
console.log('COMMIT;');
