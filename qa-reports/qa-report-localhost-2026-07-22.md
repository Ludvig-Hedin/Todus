# Browser QA report — 2026-07-22

## Result

**WARN:** public and authentication entry flows pass at desktop and mobile widths. The
authenticated product journey could not be exercised without a real test account, so
this is not a production-wide GO.

## Environment

- Production web bundle served through Vite preview at `http://localhost:3000`
- Desktop viewport: 1440 × 900
- Mobile viewport: 375 × 812
- Backend: deployed `https://api.todus.app`

## Verified

- Home renders responsively with no clipped primary content.
- Login renders responsively; “Continue with email” opens the stepped email form with
  back, email input, and send-code controls.
- Onboarding `step1.mp4`, `step2.mp4`, and `step3.mp4` return HTTP 200 with `video/mp4`.
- Production build and route navigation complete without a page crash.

## Finding and fix

The live backend returned an expected 401 from `/api/autumn/customers` on logged-out
pages because the Autumn provider probes at mount. The local server contract now treats
that probe as a valid empty customer while leaving every billing mutation protected.
The deployed backend will continue showing the old console error until this server
change is deployed.

## Evidence

- `screenshots/home-desktop.png`
- `screenshots/home-mobile.png`

## Not verified

- Authenticated inbox read/send/search/schedule
- Calendar, tasks, docs, AI, settings, billing portal
- Real OAuth/OTP completion and device/browser session handoff

These need a dedicated non-production test account or an authenticated QA fixture.
