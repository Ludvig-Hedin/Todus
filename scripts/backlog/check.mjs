#!/usr/bin/env node
/**
 * `bun backlog:check` — id allocation + integrity guard for `backlog/`.
 *
 *   node scripts/backlog/check.mjs                 report + next free id
 *   node scripts/backlog/check.mjs --json          machine-readable (for agents)
 *   node scripts/backlog/check.mjs --write-readme  regenerate the open-items table
 *
 * Exits 1 only on ERROR (same id in two lifecycle folders). Never renumbers.
 */

import {
  readHome,
  nextFreeId,
  findIdProblems,
  missingFrontMatter,
  writeReadmeTable,
  escapeCell,
  report,
  wantsJson,
  wantsWriteReadme,
} from '../agent-ops/lib.mjs';

const HOME = { baseDir: 'backlog/tasks', lifecycles: ['open', 'done'] };
const REQUIRED = ['id', 'title', 'status'];

const { items, malformed } = readHome(HOME);
const problems = findIdProblems(items);
const frontMatterProblems = missingFrontMatter(items, REQUIRED);

const open = items
  .filter((item) => item.lifecycle === 'open')
  .sort((a, b) => (a.front.priority ?? 'P9').localeCompare(b.front.priority ?? 'P9') || a.id.localeCompare(b.id));

function buildTable() {
  if (!open.length) return '_No open backlog items._';
  const rows = open.map((item) => {
    const tags = Array.isArray(item.front.tags) ? item.front.tags.join(', ') : (item.front.tags ?? '');
    return `| ${item.id} | ${escapeCell(item.front.priority ?? '—')} | ${escapeCell(tags || '—')} | [${escapeCell(item.front.title ?? item.slug)}](tasks/open/${item.file}) |`;
  });
  return ['| id | priority | tags | title |', '| --- | --- | --- | --- |', ...rows].join('\n');
}

if (wantsJson(process.argv)) {
  console.log(
    JSON.stringify(
      {
        home: 'backlog',
        counts: { total: items.length, open: open.length, done: items.length - open.length },
        nextFreeId: nextFreeId(items),
        errors: problems.errors,
        warnings: [...problems.warnings, ...frontMatterProblems, ...malformed],
        open: open.map((item) => ({
          id: item.id,
          title: item.front.title ?? item.slug,
          priority: item.front.priority ?? null,
          tags: item.front.tags ?? [],
          files: item.front.files ?? [],
          path: item.path,
        })),
      },
      null,
      2,
    ),
  );
  process.exit(problems.errors.length ? 1 : 0);
}

if (wantsWriteReadme(process.argv)) {
  const result = writeReadmeTable('backlog/README.md', buildTable());
  console.log(result.written ? 'backlog/README.md index regenerated' : `backlog/README.md unchanged — ${result.reason}`);
}

process.exit(
  report({
    label: 'backlog',
    items,
    malformed,
    problems,
    frontMatterProblems,
    extraLines: [`open: ${open.length}  done: ${items.length - open.length}`],
  }),
);
