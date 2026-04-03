import { command } from 'cmd-ts';
import postgres from 'postgres';

type DuplicateRow = Record<string, string | number | null>;

const renderRows = (title: string, rows: DuplicateRow[]) => {
  console.log(`\n${title}`);
  if (rows.length === 0) {
    console.log('  none');
    return;
  }

  for (const row of rows) {
    console.log(`  ${JSON.stringify(row)}`);
  }
};

export const auditAuthDuplicatesCommand = command({
  name: 'audit-auth-duplicates',
  description: 'Inspect auth/user duplicate risks in the connected Postgres database',
  args: {},
  handler: async () => {
    const databaseUrl = process.env.DATABASE_URL;
    if (!databaseUrl) {
      throw new Error('DATABASE_URL is required');
    }

    const sql = postgres(databaseUrl);

    try {
      const normalizedUsers = await sql<DuplicateRow[]>`
        select lower(email) as normalized_email, count(*)::int as duplicate_count
        from mail0_user
        group by lower(email)
        having count(*) > 1
        order by duplicate_count desc, normalized_email asc
      `;

      const duplicateAccounts = await sql<DuplicateRow[]>`
        select provider_id, account_id, count(*)::int as duplicate_count
        from mail0_account
        group by provider_id, account_id
        having count(*) > 1
        order by duplicate_count desc, provider_id asc, account_id asc
      `;

      const duplicateConnections = await sql<DuplicateRow[]>`
        select lower(email) as normalized_email, count(*)::int as duplicate_count
        from mail0_connection
        group by lower(email)
        having count(*) > 1
        order by duplicate_count desc, normalized_email asc
      `;

      renderRows('Duplicate users by normalized email', normalizedUsers);
      renderRows('Duplicate auth accounts by provider/account id', duplicateAccounts);
      renderRows('Duplicate connections by normalized email', duplicateConnections);
    } finally {
      await sql.end();
    }
  },
});
