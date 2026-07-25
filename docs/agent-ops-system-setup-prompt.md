# Agent ops system — setup prompt (portable)

Paste the block below into Claude Code in the target repo. It recreates the
Sajt "agent operating system": `backlog/`, `user-tasks/`, `changelog/entries/`,
`docs/agent-memory/` (incl. active-work + regressions), and docs governance.

---

## PROMPT — copy from here

Set up an **agent operating system** in this repo: a committed, file-per-item
structure that lets many coding agents and humans share one branch without losing
work, without a monolithic TODO file, and without an agent having to read 5000
lines to find one task.

Read the repo first (`README`, `CLAUDE.md`/`AGENTS.md`, `package.json`, any
existing `BACKLOG.md` / `TODO.md` / `CHANGELOG.md` / `docs/`). Match the existing
stack, package manager, and language conventions. Do not install dependencies.
Do not reformat unrelated files.

### Core principle

Every list that used to be a single growing Markdown file becomes a **folder,
one file per item**, with an `NNNN-<slug>.md` global sequence and YAML front
matter. Reason: an agent can load exactly one item in one context window, and two
agents adding items in parallel touch different files instead of conflicting on
one.

Four separate homes, never mixed:

| what | where | who acts |
| --- | --- | --- |
| code / agent follow-ups, bugs, nits, deferred work | `backlog/` | an agent, autonomously |
| work needing human hands outside the code (env vars, external accounts, dashboards, signing, live-credential verification) | `user-tasks/` | the owner |
| history — what shipped | `changelog/entries/` | written at commit time |
| durable shared facts, gotchas, coordination | `docs/agent-memory/` | anyone who learns one |

Plus: **plans = intent · feature docs = reality · backlog = remaining work ·
git = history.** Never conflate them, never keep two canonical docs for one topic.

### 1. `backlog/`

```
backlog/
  README.md
  tasks/open/      NNNN-<slug>.md   # live, actionable
  tasks/done/      NNNN-<slug>.md   # archive, not worked
```

Front matter: `id`, `title`, `status` (open|done), optional `priority` (P0–P4),
optional `tags`, best-effort `files` (paths the fix touches), `created`.
Body: the problem verbatim, `file:line` refs, and a **"Fix shape"** section when
the shape is known.

`README.md` documents the convention and holds a generated index table of open
items. Closing an item = move to `tasks/done/`, flip `status: done`, append a
completion note with the date and **evidence** (what was observed, not assumed).

An agent may fix an open item inline when confident and low-risk.

### 2. `user-tasks/`

Same shape (`README.md`, `tasks/open/`, `tasks/done/`), separate id sequence.
Front matter adds `area` (auth, billing, infra, security, qa, ops, legal, apps,
integrations, analytics, seo, support, misc — adapt to this repo) and `source`.

Bodies use checkboxes and must state the **exact** thing to do: the env var name
*and where it lives* (which host's project env vs which backend), the dashboard,
the account. A README table lists open tasks with id, priority, area, title, and
the count of unchecked boxes, plus a "Do first — P0 blockers" section.

Rule for agents: work a human must do outside the codebase goes **here**, never
buried in `backlog/`. Never tick a box from a presence check when the claim is
about behaviour — a variable being *set* is not a webhook being *delivered*.

### 3. `changelog/`

```
changelog/
  README.md
  entries/unreleased/   NNNN-<slug>.md   # committed, not yet tagged
  entries/released/                      # shipped under a version tag
  entries/archived/                      # legacy / unversioned history
```

Front matter: `id`, `title`, `status`, `category` (Added | Changed | Fixed |
Security | Removed | Docs), optional `release_date`, `version`, `tags`,
`commits`, `files`.

Entries are **history, never tasks** — a deferred item goes to `backlog/`, not
into a changelog entry as a TODO. Bodies are prose explaining what changed and
why, not a bullet dump. Status is section-driven, not date-driven: untagged =
unreleased. If a root `CHANGELOG.md` exists, migrate its entries into
`entries/` (verbatim, no rewriting) and leave the root file as a pointer stub.

One entry per meaningful item, written in the **same commit** as the change.

### 4. `docs/agent-memory/`

```
docs/agent-memory/
  README.md          # index + authority boundary
  active-work.md     # who is touching which files right now
  regressions.md     # every fixed bug: symptom / cause / fix / test / keywords
  <topic>.md         # one focused durable fact per file
```

`README.md` must state the **authority boundary**: canonical docs and the code
outrank this memory. This folder is for durable repo gotchas, surprising
conventions, recurring debugging lessons, agent-coordination rules, and
non-obvious operational facts — *not* for product scope, feature status, routes,
or roadmap. No session logs, no chain-of-thought.

`active-work.md` is an advisory table: `Task | Agent | Branch | Touched areas
(globs) | Status | Updated`. Read at session start; scan for overlap before
claiming files; edit only your own row; clear it when the work lands.

`regressions.md` is grep-first: before reviewing or "fixing" something, search it
so a fixed bug is not reintroduced.

### 5. Docs governance

- `docs/README.md` is the documentation **map** — every context/spec file listed
  with a one-line purpose. Any new doc must be registered there.
- Plans live under `docs/plans/{open,doing,done/YYYY,archive}/` and move through
  that lifecycle. Never invent a second plans folder.
- Precedence, written down explicitly: owner directive → product source of truth
  (`prd.md` or equivalent) → code/tests → canonical feature docs → plans →
  audits → agent memory.
- Never document planned functionality as implemented. Distinguish **Working ·
  Partial · Static UI · Planned**.

### 6. Scripts (write these, keep them dependency-free Node ESM)

- `scripts/backlog/check.mjs` → `backlog:check`. Prints the **next free id** and
  guards the two failure modes that actually happen: (a) ERROR — the same id in
  two lifecycle folders (an agent reads the stale copy and re-opens closed
  findings); (b) WARNING — id reuse, so "see 0533" is ambiguous. Never renumber
  history. Exit 1 on ERROR. `--json` flag for agents.
- The same script (or a sibling `--write-readme` flag) regenerates the README
  index table from the files on disk, so the table can never drift.
- Mirror it for `user-tasks` and `changelog` if cheap; at minimum, **id
  allocation must never be done by eye.**
- Optional: `scripts/docs/check.mjs` → `docs:check`, a report-only structural
  validator for the governed doc folders (front matter present, no empty
  lifecycle dirs, no broken relative links, no forbidden legacy folders).
- Wire the scripts into `package.json` using this repo's package manager.

### 7. `CLAUDE.md` (and `AGENTS.md`, kept byte-identical)

Append a short **Team workflow** section — do not rewrite what is already there:

1. Branch policy for this repo (state it explicitly, whatever it is).
2. **Stay in your lane.** Touch only files for the current task. Never
   `git add .` / `-A` — stage owned paths explicitly. Claim files in
   `docs/agent-memory/active-work.md`.
3. **Document as you go.** After any meaningful change, update the canonical doc
   and register any new doc in `docs/README.md`.
4. **Review before push.** Self-review the diff; spawn a reviewer subagent for
   anything touching auth, payments, schema, webhooks, security, or 3+ files.
5. **Commit + changelog together.** One changelog entry file per meaningful item,
   in the same commit.
6. **Track follow-ups.** Code/agent work → `backlog/`. Human hands → `user-tasks/`.
   Scope/priority/risk decisions → ask the owner. Never bury a human action item
   in `backlog/`.
7. **Verify before finishing** — list this repo's actual test/lint/typecheck/build
   commands.

### 8. Bootstrap from what already exists

Do not start empty. Migrate real content:

- Split any existing `BACKLOG.md` / `TODO.md` into `backlog/tasks/open/*.md`,
  verbatim — no summarising, no dropping items.
- Split any existing `CHANGELOG.md` into `changelog/entries/`, verbatim, keeping
  non-entry prose in the README under "Preserved prose" so nothing is lost.
- Sweep the code for `TODO:` / `FIXME:` comments with real deferred work and file
  the substantial ones as backlog items (leave the comments, add the ticket ref).
- Seed `docs/agent-memory/` with what you learned reading the repo: the stack,
  load-bearing decisions, and any gotcha you hit during this setup.
- After splitting, **diff the split against the original** and report anything
  the migration dropped. This is where these migrations actually fail.

### 9. Constraints

- Invent nothing. If a fact is not in the repo, do not write it into a doc.
- Do not delete or overwrite an existing doc without telling me first.
- Ask before changing branch policy or any existing workflow rule.
- Keep every README under ~120 lines; generated index tables don't count.

### 10. Report back

Finish with: the tree you created, the counts (backlog items / user tasks /
changelog entries migrated), what the migration diff showed as dropped or
ambiguous, the scripts and their npm-script names, the exact block appended to
`CLAUDE.md`, and anything you deliberately left out.

## PROMPT — copy to here
