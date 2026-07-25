---
id: 0283
title: "Fix — review follow-up for shard paging and compound parsing regressions"
status: archived
category: Fixed
release_date: 2026-04-29
source: CHANGELOG.md
---

## [2026-04-29] Fix — review follow-up for shard paging and compound parsing regressions

- [Fix] **Shard-backed mail pagination now uses an opaque composite cursor instead of a timestamp-only cutoff.** `apps/server/src/routes/agent/db/index.ts`, `apps/server/src/routes/agent/index.ts`, and `apps/server/src/lib/server-utils.ts` now order paged thread queries by `(latestReceivedOn DESC, id DESC)`, encode page tokens as `{ latestReceivedOn, id }`, and propagate the DB helper's real `nextPageToken` through shard aggregation. This prevents same-timestamp rows from being skipped at shard page boundaries and keeps single-shard exact-page-size pagination working.
- [Fix] **Web NLP quick-add no longer turns trailing numbers into times unless a date marker exists.** `apps/web/lib/nlp/parse-natural-language.ts` now gates the bare tail-number pattern behind a detected relative/weekday date, so inputs like `Buy milk 2` keep the `2` in the task title instead of silently creating a due date.
- [Fix] **Web compound parsing now matches native cleanup/reference handling for Swedish follow-up words.** The same parser now recognizes ASCII spellings like `i forvag` / `efterat`, treats `sen` / `sedan` as true after-references instead of leaving them in the captured title, and strips those markers back out after resolving the relative date.
- [Fix] **Native compound-intent parsing only splits on conjunctions when the right-hand clause actually starts like a new action.** Both `apps/ios/Todus/Todus/Services/Parsing/CompoundIntentParser.swift` and `apps/macos/TodusMac/Services/Tasks/CompoundIntentParser.swift` now require a likely verb-led clause after `and` / `och`, preventing ordinary titles like `Lunch with Sarah and Tom tomorrow` from being broken into multiple captures. The macOS classifier now also checks email intents before event keywords using word-boundary matching, so phrases like `maila honom presentationen innan` stay email intents instead of incorrectly opening calendar creation.
- [Verification] **Native parser regression coverage expanded.** `apps/ios/Todus/TodusTests/LocalTaskParsingServiceTests.swift` now covers the ordinary-title no-split case and confirms verb-led follow-up clauses still split into separate intents.
