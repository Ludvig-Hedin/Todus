/**
 * Auto-detects which migrations are already applied by comparing DB state
 * against the full migration lifecycle (handles tables that were created,
 * then later dropped or renamed). Inserts baselined records so db:migrate
 * can resume from the first genuinely missing migration.
 *
 * Usage:
 *   DATABASE_URL="postgresql://..." node scripts/baseline-migrations.mjs
 */
import postgres from 'postgres';
import { readFileSync } from 'fs';
import { createHash } from 'crypto';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(__dirname, '../src/db/migrations');
const journal = JSON.parse(readFileSync(join(migrationsDir, 'meta/_journal.json'), 'utf8'));

// ── Parse full lifecycle from all migration files ─────────────────────────────

const lifecycle = {
  // tableName → idx of migration that drops it (after creating it)
  tableDroppedAt: {},
  // originalName → { idx, newName } for renames
  tableRenamedAt: {},
  // "table.col" → idx of migration that drops the column
  columnDroppedAt: {},
  // indexName → idx of migration that drops the index
  indexDroppedAt: {},
};

for (const entry of journal.entries) {
  const migSql = readFileSync(join(migrationsDir, entry.tag + '.sql'), 'utf8');

  for (const m of migSql.matchAll(/DROP TABLE(?:\s+IF EXISTS)?\s+"([^"]+)"/gi)) {
    lifecycle.tableDroppedAt[m[1]] = entry.idx;
  }
  for (const m of migSql.matchAll(/ALTER TABLE\s+"([^"]+)"\s+RENAME TO\s+"([^"]+)"/gi)) {
    lifecycle.tableRenamedAt[m[1]] = { idx: entry.idx, newName: m[2] };
  }
  for (const m of migSql.matchAll(/ALTER TABLE\s+"([^"]+)"\s+RENAME COLUMN\s+"([^"]+)"\s+TO\s+"([^"]+)"/gi)) {
    lifecycle.columnDroppedAt[`${m[1]}.${m[2]}`] = entry.idx; // old col gone
  }
  for (const m of migSql.matchAll(/ALTER TABLE\s+"([^"]+)"\s+DROP COLUMN(?:\s+IF EXISTS)?\s+"([^"]+)"/gi)) {
    lifecycle.columnDroppedAt[`${m[1]}.${m[2]}`] = entry.idx;
  }
  for (const m of migSql.matchAll(/DROP INDEX(?:\s+IF EXISTS)?\s+(?:"[^"]+"\.)?"([^"]+)"/gi)) {
    lifecycle.indexDroppedAt[m[1]] = entry.idx;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function tableAlreadyHandled(tableName, migIdx, existingTables) {
  if (existingTables.has(tableName)) return true; // still exists
  const dropped = lifecycle.tableDroppedAt[tableName];
  if (dropped !== undefined && dropped > migIdx) return true; // created then dropped later
  const renamed = lifecycle.tableRenamedAt[tableName];
  if (renamed && renamed.idx > migIdx) {
    // renamed later — the new name should exist
    return existingTables.has(renamed.newName);
  }
  return false;
}

function columnAlreadyHandled(tableCol, migIdx, existingColumns) {
  if (existingColumns.has(tableCol)) return true;
  const dropped = lifecycle.columnDroppedAt[tableCol];
  return dropped !== undefined && dropped > migIdx;
}

function indexAlreadyHandled(indexName, migIdx, existingIndexes) {
  if (existingIndexes.has(indexName)) return true;
  const dropped = lifecycle.indexDroppedAt[indexName];
  return dropped !== undefined && dropped > migIdx;
}

function isMigrationAlreadyApplied(entry, migSql, existingTables, existingColumns, existingIndexes) {
  // Tables created
  for (const m of migSql.matchAll(/CREATE TABLE(?:\s+IF NOT EXISTS)?\s+"([^"]+)"/gi)) {
    if (!tableAlreadyHandled(m[1], entry.idx, existingTables)) return false;
  }
  // Tables renamed (ALTER TABLE old RENAME TO new)
  for (const m of migSql.matchAll(/ALTER TABLE\s+"([^"]+)"\s+RENAME TO\s+"([^"]+)"/gi)) {
    // The rename is applied if old doesn't exist AND new does
    if (existingTables.has(m[1])) return false; // old still exists → not yet renamed
    if (!existingTables.has(m[2])) return false; // new doesn't exist → rename not done
  }
  // Columns added
  for (const m of migSql.matchAll(/ALTER TABLE\s+"([^"]+)"\s+ADD COLUMN(?:\s+IF NOT EXISTS)?\s+"([^"]+)"/gi)) {
    if (!columnAlreadyHandled(`${m[1]}.${m[2]}`, entry.idx, existingColumns)) return false;
  }
  // Columns renamed
  for (const m of migSql.matchAll(/ALTER TABLE\s+"([^"]+)"\s+RENAME COLUMN\s+"([^"]+)"\s+TO\s+"([^"]+)"/gi)) {
    // rename applied if old col gone and new col exists
    if (existingColumns.has(`${m[1]}.${m[2]}`)) return false; // old still there → not renamed
    if (!existingColumns.has(`${m[1]}.${m[3]}`)) return false; // new not there → not done
  }
  // Indexes created
  for (const m of migSql.matchAll(/CREATE(?:\s+UNIQUE)?\s+INDEX(?:\s+IF NOT EXISTS)?\s+"([^"]+)"/gi)) {
    if (!indexAlreadyHandled(m[1], entry.idx, existingIndexes)) return false;
  }
  return true;
}

// ── Main ──────────────────────────────────────────────────────────────────────

const sql = postgres(process.env.DATABASE_URL, { ssl: 'require' });

async function main() {
  await sql`CREATE SCHEMA IF NOT EXISTS drizzle`;
  await sql`
    CREATE TABLE IF NOT EXISTS drizzle.__drizzle_migrations (
      id         SERIAL PRIMARY KEY,
      hash       text   NOT NULL,
      created_at bigint
    )
  `;

  const [{ n }] = await sql`SELECT count(*)::int AS n FROM drizzle.__drizzle_migrations`;
  if (n > 0) {
    console.log(`Already has ${n} rows — nothing to do.`);
    await sql.end();
    return;
  }

  const [existingTablesRows, existingColumnsRows, existingIndexesRows] = await Promise.all([
    sql`SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE 'mail0_%'`,
    sql`SELECT table_name, column_name FROM information_schema.columns WHERE table_schema='public' AND table_name LIKE 'mail0_%'`,
    sql`SELECT indexname FROM pg_indexes WHERE schemaname='public' AND tablename LIKE 'mail0_%'`,
  ]);

  const existingTables  = new Set(existingTablesRows.map(r => r.table_name));
  const existingColumns = new Set(existingColumnsRows.map(r => `${r.table_name}.${r.column_name}`));
  const existingIndexes = new Set(existingIndexesRows.map(r => r.indexname));

  console.log(`DB has ${existingTables.size} mail0_* tables, ${existingColumns.size} columns, ${existingIndexes.size} indexes.`);

  const toBaseline = [];
  let firstNew = null;

  for (const entry of journal.entries) {
    const migSql = readFileSync(join(migrationsDir, entry.tag + '.sql'), 'utf8');
    const hash   = createHash('sha256').update(migSql).digest('hex');
    const applied = isMigrationAlreadyApplied(entry, migSql, existingTables, existingColumns, existingIndexes);

    if (applied) {
      toBaseline.push({ ...entry, hash });
      console.log(`  ✓ ${entry.tag}`);
    } else {
      firstNew = entry;
      console.log(`  ✗ ${entry.tag}  ← first migration to apply`);
      break;
    }
  }

  if (toBaseline.length === 0) {
    console.log('\nNothing to baseline — all migrations will run fresh.');
    await sql.end();
    return;
  }

  console.log(`\nInserting ${toBaseline.length} baseline records...`);
  for (const r of toBaseline) {
    await sql`INSERT INTO drizzle.__drizzle_migrations (hash, created_at) VALUES (${r.hash}, ${r.when})`;
  }

  const last = toBaseline[toBaseline.length - 1];
  console.log(`\nBaselined up to ${last.tag} (idx ${last.idx}).`);
  if (firstNew) console.log(`First migration to apply: ${firstNew.tag}`);
  console.log('\nRun: bun db:migrate');

  await sql.end();
}

main().catch(e => { console.error(e); process.exit(1); });
