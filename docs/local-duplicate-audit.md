## Running the duplicate audit locally

To validate the marketing email dedupe and clean duplicates before you run against production, you can exercise the same scripts locally:

1. **Wire a local Postgres connection into Hyperdrive.** Open `apps/server/wrangler.jsonc` and add `localConnectionString` under the `hyperdrive` binding that the worker uses:

   ```json
   "hyperdrive": [
     {
       "binding": "HYPERDRIVE",
       "id": "e53252a4a8394ddab18f855b93601978",
       "localConnectionString": "postgres://postgres:postgres@localhost:5432/todus"
     }
   ]
   ```

   When you run `wrangler dev`, Wrangler injects that string into `env.HYPERDRIVE.connectionString`, so the backend uses your local Postgres instance just like production but without requiring a `DATABASE_URL` dashboard entry. You can also point the string to any other reachable development database.

2. **Source `DATABASE_URL` for the audit script.** The helper `scripts/audit-auth-duplicates.ts` still expects a `DATABASE_URL` env var, so before running it set:

   ```bash
   export DATABASE_URL="postgres://postgres:postgres@localhost:5432/todus"
   pnpm scripts audit-auth-duplicates
   ```

   The command reports any normalized user emails, `(provider_id, account_id)` tuples, or normalized connection emails that appear more than once in the configured database.

3. **Clear duplicates if necessary.** If the script prints rows, rerun the migration `apps/server/src/db/migrations/0048_marketing_email_idempotency.sql` while pointed at the same database: it deletes older duplicate `mail0_account` rows before adding the uniqueness constraint, so running it locally will remove duplicates and stop future repeats. After the migration completes, rerun the audit script to verify each section now prints `none`.

4. **Repeat with production data.** Once you have a Hyperdrive production connection string (the value you used when running `wrangler hyperdrive create <name> --connection-string="postgres://..."`), source it as `DATABASE_URL` and rerun the audit command against production data. Use the same migration if duplicates exist; with the ledger constraints in place and clean data, future marketing campaign sends cannot insert duplicates or more than one entry per normalized email per day.【0†source】citeturn0view0
