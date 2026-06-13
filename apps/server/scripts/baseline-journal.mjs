// One-off: repair a drifted production __drizzle_migrations table so
// `drizzle-kit migrate` stops replaying already-applied migrations.
//
// Emits ADDITIVE, IDEMPOTENT SQL to STDOUT (hashes are not secrets):
//   - no TRUNCATE / UPDATE / DELETE — never touches existing rows
//   - inserts only journal entries whose `created_at` (folderMillis) is not
//     already present, so re-running is a no-op
//
// Hashes come from drizzle's own readMigrationFiles, so they are identical to
// what `drizzle-kit migrate` computes at runtime. __drizzle_migrations is
// migrate-only metadata, never read by the running app.
import { readMigrationFiles } from 'drizzle-orm/migrator';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsFolder = resolve(here, '../src/db/migrations');

const migrations = readMigrationFiles({ migrationsFolder });

// Escape single quotes defensively (hex hashes never contain them, but be safe).
const values = migrations
  .map((m) => `    ('${m.hash.replace(/'/g, "''")}', ${m.folderMillis})`)
  .join(',\n');

console.log(`-- baseline ${migrations.length} journal migrations (additive, idempotent)`);
console.log('BEGIN;');
console.log('INSERT INTO "drizzle"."__drizzle_migrations" (hash, created_at)');
console.log('SELECT v.hash, v.created_at');
console.log('FROM (VALUES');
console.log(values);
console.log(') AS v(hash, created_at)');
console.log('WHERE NOT EXISTS (');
console.log('  SELECT 1 FROM "drizzle"."__drizzle_migrations" m WHERE m.created_at = v.created_at');
console.log(');');
console.log('COMMIT;');
