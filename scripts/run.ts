import { auditAuthDuplicatesCommand } from './audit-auth-duplicates';
import { sendEmailsCommand } from './send-emails/index';
// import { seedStyleCommand } from './seed-style/seeder';
import { subcommands, run } from 'cmd-ts';

const app = subcommands({
  name: 'scripts',
  cmds: {
    'audit-auth-duplicates': auditAuthDuplicatesCommand,
    // 'seed-style': seedStyleCommand,
    'send-emails': sendEmailsCommand,
  },
});

await run(app, process.argv.slice(2));
process.exit(0);
