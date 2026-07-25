# Never allocate an id by eye

`backlog/`, `user-tasks/` and `changelog/` each use a 4-digit sequence shared across
their lifecycle folders. Picking "the next one" by looking at `ls` output is how two
items end up as `0473` and how "see 0533" becomes ambiguous.

```bash
bun backlog:check      # next free id, plus collisions
bun user-tasks:check
bun changelog:check
```

Each accepts `--json` (for agents) and `--write-readme` (regenerates that folder's index
table from the files on disk, so the table cannot drift).

The check scripts fail (exit 1) on one thing only: **the same id in two lifecycle
folders**, because an agent that reads the stale copy will re-open closed work. Id reuse
inside one folder is a warning. Neither is ever fixed by renumbering history — fix the
newer file.
