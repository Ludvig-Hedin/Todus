# Scripts Guide

## Active App Commands

### iOS (`apps/ios`)
```bash
pnpm ios
pnpm ios:simulator
pnpm ios:build:preview
pnpm ios:build:production
```

### macOS Desktop Wrapper (`apps/macos`)
```bash
pnpm macos
```

### Web + Backend
```bash
pnpm dev
pnpm build:frontend
pnpm deploy:frontend
pnpm deploy:backend
```

## Removed From Active Use

The old `native:*` scripts were removed from root `package.json`.

Legacy app implementations are archived under `apps/archived/*` and should not be used for active development.
