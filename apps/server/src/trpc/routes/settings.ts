import { createRateLimiterMiddleware, privateProcedure, publicProcedure, router } from '../trpc';
import {
  defaultUserSettings,
  mergeUserSettings,
  userSettingsSchema,
  type UserSettings,
} from '../../lib/schemas';
import { getZeroDB } from '../../lib/server-utils';
import { Ratelimit } from '@upstash/ratelimit';

export const settingsRouter = router({
  get: publicProcedure
    .use(
      createRateLimiterMiddleware({
        limiter: Ratelimit.slidingWindow(120, '1m'),
        generatePrefix: ({ sessionUser }) => `ratelimit:get-settings-${sessionUser?.id}`,
      }),
    )
    .query(async ({ ctx }) => {
      if (!ctx.sessionUser) return { settings: defaultUserSettings };

      const { sessionUser } = ctx;
      const db = await getZeroDB(sessionUser.id);
      const result: any = await db.findUserSettings();

      // Returning null here when there are no settings so we can use the default settings with timezone from the browser
      if (!result) return { settings: defaultUserSettings };

      const settingsRes = userSettingsSchema.safeParse(result.settings);
      if (!settingsRes.success) {
        ctx.c.executionCtx.waitUntil(db.updateUserSettings(defaultUserSettings));
        return { settings: defaultUserSettings };
      }

      return { settings: mergeUserSettings(undefined, settingsRes.data) };
    }),

  save: privateProcedure.input(userSettingsSchema.partial()).mutation(async ({ ctx, input }) => {
    const { sessionUser } = ctx;
    const db = await getZeroDB(sessionUser.id);
    const existingSettings: any = await db.findUserSettings();

    if (existingSettings) {
      // Parse existing settings through the schema before merging to avoid propagating malformed data
      const parsed = userSettingsSchema.safeParse(existingSettings.settings);
      const base: UserSettings | undefined = parsed.success ? parsed.data : undefined;
      const newSettings: any = mergeUserSettings(base, input);
      await db.updateUserSettings(newSettings);
    } else {
      await db.insertUserSettings(mergeUserSettings(undefined, input));
    }

    return { success: true };
  }),
});
