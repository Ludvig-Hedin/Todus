# Security

## Reporting a vulnerability

Please report security issues privately (do not open a public issue). If you use GitHub, use [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) for this repository when enabled, or contact the maintainers directly.

## Secrets and open-source contributors

- **Never commit** API keys, OAuth client secrets, database passwords, JWT signing secrets, or tokens. Use `.env` / `.dev.vars` locally; both are gitignored.
- **Production and staging** on Cloudflare: use `wrangler secret put <NAME>` or the dashboard. Do not put real secrets in `wrangler.jsonc` `vars` — that file is tracked in git.
- **Forks**: Replace Hyperdrive, KV, R2, and queue IDs in `wrangler.jsonc` with resources in your own Cloudflare account, or your deploy will target the wrong infrastructure.
- **OAuth**: Google *client ID* for installed/mobile apps is often treated as public; **client secret** and refresh tokens must stay server-side only.
- **Frontend `VITE_PUBLIC_*`**: Values are embedded in the browser bundle. Do not put anything there that must stay confidential (e.g. treat `VITE_PUBLIC_*` like public data).

CI runs [Gitleaks](https://github.com/gitleaks/gitleaks) on pull requests to catch common accidental secret commits.
