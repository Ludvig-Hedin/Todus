# The frontend app is `apps/web`, and the root deploy scripts still say otherwise

`apps/web` (`@zero/web`) is the entire user-facing surface: marketing, auth, mail,
settings, developer pages. `apps/mail` (`@zero/mail`) is a **read-only archive** — never
edit it. `apps/archived/` is reference only.

The trap: the root `package.json` still points its frontend scripts at the archive.

```jsonc
"build:frontend":  "bun run --filter=@zero/mail build",   // legacy archive
"deploy:frontend": "bun run --filter=@zero/mail deploy",  // legacy archive
```

Ship the real app with:

```bash
bun run --filter=@zero/web build
bun run --filter=@zero/web deploy
```

`bun dev` / `bun web` already run `apps/web` + `apps/server`, so only the build/deploy
scripts are wrong.
