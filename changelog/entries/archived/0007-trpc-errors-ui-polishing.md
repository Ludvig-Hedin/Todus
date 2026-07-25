---
id: 0007
title: "tRPC Errors & UI Polishing"
status: archived
category: Changed
release_date: 2026-02-27
source: CHANGELOG.md
---

## [2026-02-27] tRPC Errors & UI Polishing

### Fixed

- **tRPC API**: Resolved 500 Internal Server Error in `brain.generateSummary` caused by missing Vectorize indexes (`VECTOR_GET_ERROR`) by implementing a try-catch fallback.
- **UI Warnings**: Fixed `react-resizable-panels` console warnings by strictly defining `id` and `order` properties for all `ResizablePanel` components, and restoring missing `<ResizableHandle />` elements.
