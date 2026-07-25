---
id: 0249
title: "Feature — iOS AI chat: attachment thumbnails, full-screen preview, vision MIME fix"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Feature — iOS AI chat: attachment thumbnails, full-screen preview, vision MIME fix

- [Feature] **iOS:** Sent attachments in the user bubble now show a real image thumbnail (with `loadImage` fallback when thumbnail decode fails) and a short label (“Image”, “Image 2”, or “File (PDF)”) instead of the raw UUID filename. Tap opens a full-screen black preview with **Copy** (image to pasteboard) and **Save** (Photo Library; `NSPhotoLibraryAddUsageDescription` added). Non-image files get **Share** in the same sheet.
- [Fix] **iOS:** `AttachmentService.mimeType` can sniff JPEG/PNG/GIF/WebP magic bytes so the server classifies borderline files as `image/*` and merges them as vision `image_url` parts (matching `mergeAttachmentsIntoLastUserMessage` in `ai.ts`).
