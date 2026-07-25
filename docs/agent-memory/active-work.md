# Active work

Advisory only — this table does not lock anything. Several agents and humans share one
working tree and one branch (`main`).

**Protocol**

1. Read this table at session start.
2. Scan for overlap before you touch files; if someone else claims your area, coordinate
   or pick different work.
3. Add **your own** row when you start; edit only your own row.
4. Clear your row when the work lands.

| Task | Agent | Branch | Touched areas (globs) | Status | Updated |
|------|-------|--------|-----------------------|--------|---------|
| _(none)_ | — | — | — | — | — |

Stale rows are worse than no rows. If a row is older than a few days and its work is in
`git log`, delete it.
