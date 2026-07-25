#!/usr/bin/env node
/**
 * `bun docs:check` — report-only structural validator for the governed doc
 * folders. It never edits anything and never fails the build; it prints what
 * drifted so a human or agent can decide.
 *
 * Checks:
 *   1. every `docs/*.md` is registered in `docs/README.md`
 *   2. plans live only under `docs/plans/{open,doing,done,archive}` — no second
 *      plans folder, no loose files at the `docs/plans/` root
 *   3. relative links inside the governed folders resolve on disk
 *   4. no empty lifecycle directory in backlog / user-tasks / changelog / plans
 */

import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join, dirname, resolve, relative } from 'node:path';
import { REPO_ROOT } from '../agent-ops/lib.mjs';

const GOVERNED_DIRS = [
  'backlog',
  'user-tasks',
  'changelog',
  'docs/agent-memory',
  'docs/plans',
];

const LIFECYCLE_DIRS = [
  'backlog/tasks/open',
  'backlog/tasks/done',
  'user-tasks/tasks/open',
  'user-tasks/tasks/done',
  'changelog/entries/unreleased',
  'changelog/entries/released',
  'changelog/entries/archived',
  'docs/plans/open',
  'docs/plans/doing',
  'docs/plans/done',
  'docs/plans/archive',
];

const findings = [];
const note = (level, message) => findings.push({ level, message });

function walk(dir, out = []) {
  const absolute = join(REPO_ROOT, dir);
  if (!existsSync(absolute)) return out;
  for (const name of readdirSync(absolute)) {
    if (name.startsWith('.')) continue;
    const rel = join(dir, name);
    if (statSync(join(REPO_ROOT, rel)).isDirectory()) walk(rel, out);
    else if (name.endsWith('.md')) out.push(rel);
  }
  return out;
}

// 1. docs/README.md is the map — every top-level docs/*.md must be listed.
const docsReadmePath = join(REPO_ROOT, 'docs/README.md');
if (existsSync(docsReadmePath)) {
  const readme = readFileSync(docsReadmePath, 'utf8');
  for (const name of readdirSync(join(REPO_ROOT, 'docs'))) {
    if (!name.endsWith('.md') || name === 'README.md') continue;
    if (!readme.includes(name)) note('WARNING', `docs/${name} is not registered in docs/README.md`);
  }
} else {
  note('WARNING', 'docs/README.md is missing — the documentation map has no home');
}

// 2. plans lifecycle
const plansRoot = join(REPO_ROOT, 'docs/plans');
if (existsSync(plansRoot)) {
  for (const name of readdirSync(plansRoot)) {
    if (name.startsWith('.')) continue;
    const isDir = statSync(join(plansRoot, name)).isDirectory();
    if (!isDir && name !== 'README.md') {
      note('WARNING', `docs/plans/${name} sits at the plans root — move it into open/ doing/ done/ archive/`);
    }
    if (isDir && !['open', 'doing', 'done', 'archive'].includes(name)) {
      note('WARNING', `docs/plans/${name}/ is not a recognised plan lifecycle folder`);
    }
  }
}

// 3. relative links resolve.
//    Archive folders are frozen history — their links point at paths that have since
//    moved, and rewriting them would falsify the record, so they are not checked.
const FROZEN = ['changelog/entries/archived', 'backlog/tasks/done', 'user-tasks/tasks/done', 'docs/plans/archive'];
const linkPattern = /\[[^\]]*\]\(([^)]+)\)/g;
for (const dir of GOVERNED_DIRS) {
  for (const file of walk(dir)) {
    if (FROZEN.some((frozen) => file.startsWith(frozen))) continue;
    const text = readFileSync(join(REPO_ROOT, file), 'utf8');
    let match;
    while ((match = linkPattern.exec(text)) !== null) {
      const target = match[1].split('#')[0].trim();
      if (!target || /^[a-z]+:/i.test(target) || target.startsWith('#') || target.startsWith('<')) continue;
      // migrated bodies mix file-relative and repo-root-relative links; accept either
      const fileRelative = resolve(join(REPO_ROOT, dirname(file)), target);
      const rootRelative = resolve(REPO_ROOT, target);
      if (!existsSync(fileRelative) && !existsSync(rootRelative)) {
        note('WARNING', `${file} links to missing path ${target}`);
      }
    }
  }
}

// 4. lifecycle folders exist and are non-empty (an empty one usually means a
//    half-finished migration, not a clean slate)
for (const dir of LIFECYCLE_DIRS) {
  const absolute = join(REPO_ROOT, dir);
  if (!existsSync(absolute)) {
    note('WARNING', `${dir}/ is missing`);
    continue;
  }
  const entries = readdirSync(absolute).filter((name) => !name.startsWith('.'));
  if (!entries.length) note('INFO', `${dir}/ is empty`);
}

const errors = findings.filter((f) => f.level === 'ERROR');
console.log(`docs:check — ${findings.length} finding(s) across ${GOVERNED_DIRS.length} governed folder(s)`);
for (const finding of findings) console.log(`${finding.level.padEnd(8)} ${finding.message}`);
if (!findings.length) console.log('clean');
console.log(`\nreport-only: ${relative(REPO_ROOT, process.cwd()) || '.'} unchanged`);
process.exit(errors.length ? 1 : 0);
