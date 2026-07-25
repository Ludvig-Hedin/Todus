#!/usr/bin/env node
/**
 * `bun changelog:check` — id allocation + integrity guard for `changelog/`.
 *
 * Lifecycle folders are `unreleased` (committed, not yet tagged), `released`
 * (shipped under a version tag) and `archived` (legacy / unversioned history).
 * Status is section-driven: whichever folder the file sits in wins.
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

const HOME = { baseDir: 'changelog/entries', lifecycles: ['unreleased', 'released', 'archived'] };
const REQUIRED = ['id', 'title', 'status', 'category'];

const { items, malformed } = readHome(HOME);
const problems = findIdProblems(items);
const frontMatterProblems = missingFrontMatter(items, REQUIRED);

const counts = {
  unreleased: items.filter((item) => item.lifecycle === 'unreleased').length,
  released: items.filter((item) => item.lifecycle === 'released').length,
  archived: items.filter((item) => item.lifecycle === 'archived').length,
};

const unreleased = items
  .filter((item) => item.lifecycle === 'unreleased')
  .sort((a, b) => b.id.localeCompare(a.id));

function buildTable() {
  if (!unreleased.length) return '_No unreleased entries._';
  const rows = unreleased.map(
    (item) =>
      `| ${item.id} | ${escapeCell(item.front.category ?? '—')} | ${escapeCell(item.front.release_date ?? '—')} | [${escapeCell(item.front.title ?? item.slug)}](entries/unreleased/${item.file}) |`,
  );
  return ['| id | category | date | title |', '| --- | --- | --- | --- |', ...rows].join('\n');
}

if (wantsJson(process.argv)) {
  console.log(
    JSON.stringify(
      {
        home: 'changelog',
        counts: { total: items.length, ...counts },
        nextFreeId: nextFreeId(items),
        errors: problems.errors,
        warnings: [...problems.warnings, ...frontMatterProblems, ...malformed],
        unreleased: unreleased.map((item) => ({
          id: item.id,
          title: item.front.title ?? item.slug,
          category: item.front.category ?? null,
          date: item.front.release_date ?? null,
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
  const result = writeReadmeTable('changelog/README.md', buildTable());
  console.log(result.written ? 'changelog/README.md index regenerated' : `changelog/README.md unchanged — ${result.reason}`);
}

process.exit(
  report({
    label: 'changelog',
    items,
    malformed,
    problems,
    frontMatterProblems,
    extraLines: [`unreleased: ${counts.unreleased}  released: ${counts.released}  archived: ${counts.archived}`],
  }),
);
