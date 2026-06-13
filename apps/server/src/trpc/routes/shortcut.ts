import { shortcutSchema } from '../../lib/shortcuts';
import { getZeroDB } from '../../lib/server-utils';
import { privateProcedure, router } from '../trpc';
import { z } from 'zod';

export const shortcutRouter = router({
  /** Returns the user's customized hotkeys (empty when they've never changed any). */
  list: privateProcedure.query(async ({ ctx }) => {
    const db = await getZeroDB(ctx.sessionUser.id);
    const rows = (await db.findUserHotkeys()) as Array<{ shortcuts: unknown }>;
    const shortcuts = (rows[0]?.shortcuts ?? []) as z.infer<typeof shortcutSchema>[];
    return { shortcuts };
  }),
  update: privateProcedure
    .input(
      z.object({
        shortcuts: z.array(shortcutSchema),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const { sessionUser } = ctx;
      const { shortcuts } = input;
      const db = await getZeroDB(sessionUser.id);
      await db.insertUserHotkeys(shortcuts as any);
    }),
});
