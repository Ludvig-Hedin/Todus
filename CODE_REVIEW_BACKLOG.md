# Code Review Backlog

Last updated: 2026-03-31

## Open Items

| ID | Title | Area | Type | Impact | Risk | Status | Summary |
|----|-------|------|------|--------|------|--------|---------|
| 001 | Inline TaskItem duplicated in home/page.tsx | web/home | design-debt | internal | low | open | `home/page.tsx` defines its own inline `TaskItem` component instead of importing the shared `components/tasks/task-item.tsx`. Both work correctly but will diverge over time. Fix: import from `@/components/tasks/task-item` and remove the inline definition. |

## Resolved in 2026-03-31 Review Session

| ID | Title | Area | Type | Status | What Changed |
|----|-------|------|------|--------|-------------|
| F01 | Missing `toast` import in chat/page.tsx | web/chat | bug | auto-fixed | Added `import { toast } from 'sonner'` — was causing runtime error on conversation load failure |
| F02 | Missing `Link` import in calendar/page.tsx | web/calendar | bug | auto-fixed | Added `import { Link } from 'react-router'` — was causing runtime error when calendar rendered |
