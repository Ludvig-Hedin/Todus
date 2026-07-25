/**
 * Shared helpers for the agent operating system checks
 * (`backlog/`, `user-tasks/`, `changelog/`).
 *
 * Dependency-free Node ESM. Every home is a folder of `NNNN-<slug>.md` files
 * split across lifecycle sub-folders, each with YAML front matter.
 *
 * Used by scripts/{backlog,user-tasks,changelog}/check.mjs.
 */

import { readdirSync, readFileSync, writeFileSync, existsSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO_ROOT = fileURLToPath(new URL('../..', import.meta.url));

const ID_FILE = /^(\d{4})-([a-z0-9][a-z0-9-]*)\.md$/;

/** Minimal YAML front-matter reader: `key: value`, `key: [a, b]`, and `- item` lists. */
export function parseFrontMatter(text) {
  if (!text.startsWith('---\n')) return {};
  const end = text.indexOf('\n---', 4);
  if (end === -1) return {};
  const block = text.slice(4, end);
  const data = {};
  let listKey = null;
  for (const rawLine of block.split('\n')) {
    const line = rawLine.replace(/\s+$/, '');
    if (!line.trim()) continue;
    const listItem = line.match(/^\s*-\s+(.*)$/);
    if (listItem && listKey) {
      data[listKey].push(stripQuotes(listItem[1]));
      continue;
    }
    const pair = line.match(/^([A-Za-z_][\w-]*):\s*(.*)$/);
    if (!pair) continue;
    const [, key, rawValue] = pair;
    const value = rawValue.trim();
    if (value === '') {
      listKey = key;
      data[key] = [];
      continue;
    }
    listKey = null;
    if (value.startsWith('[') && value.endsWith(']')) {
      const inner = value.slice(1, -1).trim();
      data[key] = inner ? inner.split(',').map((v) => stripQuotes(v.trim())).filter(Boolean) : [];
    } else {
      data[key] = stripQuotes(value);
    }
  }
  return data;
}

function stripQuotes(value) {
  return value.replace(/^["'](.*)["']$/, '$1');
}

/** Read every `NNNN-<slug>.md` in the given lifecycle folders of a home. */
export function readHome({ baseDir, lifecycles }) {
  const items = [];
  const malformed = [];
  for (const lifecycle of lifecycles) {
    const dir = join(REPO_ROOT, baseDir, lifecycle);
    if (!existsSync(dir) || !statSync(dir).isDirectory()) continue;
    for (const name of readdirSync(dir).sort()) {
      if (!name.endsWith('.md')) continue;
      if (name === 'README.md') continue;
      const path = join(dir, name);
      const match = name.match(ID_FILE);
      if (!match) {
        malformed.push({ path: relative(REPO_ROOT, path), reason: 'filename is not NNNN-<slug>.md' });
        continue;
      }
      const body = readFileSync(path, 'utf8');
      const front = parseFrontMatter(body);
      items.push({
        id: match[1],
        slug: match[2],
        lifecycle,
        file: name,
        path: relative(REPO_ROOT, path),
        front,
        body,
      });
    }
  }
  return { items, malformed };
}

/** Lowest unused 4-digit id in the home. */
export function nextFreeId(items) {
  const used = new Set(items.map((item) => Number(item.id)));
  let candidate = 1;
  while (used.has(candidate)) candidate += 1;
  return String(candidate).padStart(4, '0');
}

/**
 * The two failure modes that actually happen:
 *   ERROR   — the same id lives in two lifecycle folders (an agent reads the
 *             stale copy and re-opens closed work).
 *   WARNING — an id is reused inside one folder, so "see 0533" is ambiguous.
 * History is never renumbered; both are reported, not repaired.
 */
export function findIdProblems(items) {
  const byId = new Map();
  for (const item of items) {
    if (!byId.has(item.id)) byId.set(item.id, []);
    byId.get(item.id).push(item);
  }
  const errors = [];
  const warnings = [];
  for (const [id, group] of [...byId.entries()].sort()) {
    if (group.length < 2) continue;
    const lifecycles = new Set(group.map((item) => item.lifecycle));
    const record = { id, files: group.map((item) => item.path) };
    if (lifecycles.size > 1) errors.push({ ...record, kind: 'cross-lifecycle-duplicate' });
    else warnings.push({ ...record, kind: 'id-reuse' });
  }
  return { errors, warnings };
}

export function missingFrontMatter(items, required) {
  const problems = [];
  for (const item of items) {
    const missing = required.filter((key) => item.front[key] === undefined || item.front[key] === '');
    if (missing.length) problems.push({ path: item.path, missing });
  }
  return problems;
}

const TABLE_START = '<!-- agent-ops:index:start -->';
const TABLE_END = '<!-- agent-ops:index:end -->';

/**
 * Replace the generated index table between the marker comments so the README
 * table can never drift from the files on disk.
 */
export function writeReadmeTable(readmePath, table) {
  const absolute = join(REPO_ROOT, readmePath);
  if (!existsSync(absolute)) return { written: false, reason: `${readmePath} does not exist` };
  const text = readFileSync(absolute, 'utf8');
  const start = text.indexOf(TABLE_START);
  const end = text.indexOf(TABLE_END);
  if (start === -1 || end === -1 || end < start) {
    return { written: false, reason: `${readmePath} has no ${TABLE_START} / ${TABLE_END} markers` };
  }
  const next =
    text.slice(0, start + TABLE_START.length) + '\n\n' + table.trim() + '\n\n' + text.slice(end);
  if (next === text) return { written: false, reason: 'table already up to date' };
  writeFileSync(absolute, next);
  return { written: true };
}

export function escapeCell(value) {
  return String(value ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ').trim();
}

export function countUnchecked(body) {
  return (body.match(/^\s*[-*]\s+\[ \]/gm) || []).length;
}

/** Shared CLI reporting. Returns the process exit code. */
export function report({ label, items, malformed, problems, frontMatterProblems, extraLines = [] }) {
  const lines = [];
  lines.push(`${label}: ${items.length} item(s)`);
  lines.push(`next free id: ${nextFreeId(items)}`);
  for (const line of extraLines) lines.push(line);

  for (const entry of malformed) lines.push(`WARNING  ${entry.path} — ${entry.reason}`);
  for (const entry of frontMatterProblems) {
    lines.push(`WARNING  ${entry.path} — missing front matter: ${entry.missing.join(', ')}`);
  }
  for (const entry of problems.warnings) {
    lines.push(`WARNING  id ${entry.id} reused — ${entry.files.join(', ')}`);
  }
  for (const entry of problems.errors) {
    lines.push(`ERROR    id ${entry.id} exists in two lifecycle folders — ${entry.files.join(', ')}`);
  }
  if (!problems.errors.length) lines.push('no id collisions across lifecycle folders');

  console.log(lines.join('\n'));
  return problems.errors.length ? 1 : 0;
}

export function wantsJson(argv) {
  return argv.includes('--json');
}

export function wantsWriteReadme(argv) {
  return argv.includes('--write-readme');
}
