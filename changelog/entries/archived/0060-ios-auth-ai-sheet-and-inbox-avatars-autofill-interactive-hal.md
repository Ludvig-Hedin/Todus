---
id: 0060
title: "iOS Auth, AI Sheet, and Inbox Avatars — autofill + interactive half sheet + robust fallbacks"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Auth, AI Sheet, and Inbox Avatars — autofill + interactive half sheet + robust fallbacks

### Auth

- **Email OTP autofill improvements**: Login email field now uses iOS email autofill hints (`textContentType(.emailAddress)`) and supports submit from keyboard. OTP field keeps native one-time-code autofill and uses a done submit label.

### AI Chat Sheet

- **Half-page AI sheet**: AI chat now opens with a 50% height detent and can expand to full screen.
- **Background remains interactive at half detent**: Enabled background interaction up to the half detent so underlying page context remains visible and scrollable while the AI sheet is half-open.

### Inbox Avatars

- **No more blank avatar slots**: Sender avatar view now always renders initials with a colored circle as a guaranteed base layer.
- **More resilient fallbacks**: Added local domain fallback URL waterfall (`/favicon.ico`, `apple-touch-icon`, DuckDuckGo icon API, Google S2 favicon) when backend avatar resolution is slow/fails.
- **Subdomain and edge-case handling**: Added normalization + root-domain extraction with common multi-part TLD support (`co.uk`, `com.au`, etc.) and `www.` host variants.
- **Cache normalization**: Avatar cache now keys by normalized lowercase email to avoid misses from casing/whitespace differences.

### Files

- `apps/ios/Todus/Todus/Features/Auth/AuthView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`
