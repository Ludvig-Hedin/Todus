#!/usr/bin/env node
/**
 * `bun user-tasks:check` — id allocation + integrity guard for `user-tasks/`
 * (work a human must do outside the codebase). Same contract as backlog:check;
 * the table additionally reports each task's area and unchecked-box count.
 */

import {
  readHome,
  nextFreeId,
  findIdProblems,
  missingFrontMatter,
  writeReadmeTable,
  escapeCell,
  countUnchecked,
  report,
  wantsJson,
  wantsWriteReadme,
} from '../agent-ops/lib.mjs';

const HOME = { baseDir: 'user-tasks/tasks', lifecycles: ['open', 'done'] };
const REQUIRED = ['id', 'title', 'status', 'area'];

const { items, malformed } = readHome(HOME);
const problems = findIdProblems(items);
const frontMatterProblems = missingFrontMatter(items, REQUIRED);

const open = items
  .filter((item) => item.lifecycle === 'open')
  .map((item) => ({ ...item, todo: countUnchecked(item.body) }))
  .sort((a, b) => (a.front.priority ?? 'P9').localeCompare(b.front.priority ?? 'P9') || a.id.localeCompare(b.id));

function buildTable() {
  if (!open.length) return '_No open user tasks._';
  const blockers = open.filter((item) => item.front.priority === 'P0');
  const rows = open.map(
    (item) =>
      `| ${item.id} | ${escapeCell(item.front.priority ?? '—')} | ${escapeCell(item.front.area ?? '—')} | [${escapeCell(item.front.title ?? item.slug)}](tasks/open/${item.file}) | ${item.todo} |`,
  );
  const table = ['| id | priority | area | title | open boxes |', '| --- | --- | --- | --- | --- |', ...rows].join('\n');
  const doFirst = blockers.length
    ? ['', '### Do first — P0 blockers', '', ...blockers.map((item) => `- **${item.id}** — [${escapeCell(item.front.title ?? item.slug)}](tasks/open/${item.file}) (${item.todo} open box(es))`)].join('\n')
    : ['', '### Do first — P0 blockers', '', '_None._'].join('\n');
  return `${table}\n${doFirst}`;
}

if (wantsJson(process.argv)) {
  console.log(
    JSON.stringify(
      {
        home: 'user-tasks',
        counts: { total: items.length, open: open.length, done: items.length - open.length },
        nextFreeId: nextFreeId(items),
        errors: problems.errors,
        warnings: [...problems.warnings, ...frontMatterProblems, ...malformed],
        open: open.map((item) => ({
          id: item.id,
          title: item.front.title ?? item.slug,
          priority: item.front.priority ?? null,
          area: item.front.area ?? null,
          source: item.front.source ?? null,
          uncheckedBoxes: item.todo,
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
  const result = writeReadmeTable('user-tasks/README.md', buildTable());
  console.log(result.written ? 'user-tasks/README.md index regenerated' : `user-tasks/README.md unchanged — ${result.reason}`);
}

process.exit(
  report({
    label: 'user-tasks',
    items,
    malformed,
    problems,
    frontMatterProblems,
    extraLines: [
      `open: ${open.length}  done: ${items.length - open.length}`,
      `unchecked boxes across open tasks: ${open.reduce((sum, item) => sum + item.todo, 0)}`,
    ],
  }),
);
