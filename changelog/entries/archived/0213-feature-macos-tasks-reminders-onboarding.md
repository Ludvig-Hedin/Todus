---
id: 0213
title: "Feature — macOS Tasks: Reminders + onboarding"
status: archived
category: Added
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Feature — macOS Tasks: Reminders + onboarding

- [UI] Tasks toolbar: removed per–view-mode hint text and the “completed tasks in List” note; segmented control track now uses a `Capsule` so the outer chrome matches the inner pills.
- [Feature] “Connect Apple Reminders” on the Tasks page and a new onboarding step (step 3 of 4) after Calendar, aligned with iOS; EventKit sync uses the same flow as iOS (import + push existing tasks).
- [Feature] Connected Services “Connect” for Apple Reminders now requests Reminders permission instead of only toggling a flag; added Reminders entitlement and `NSRemindersUsageDescription`.
- [Migration] Users who already finished startup onboarding before this release skip the new Reminders screen once.
