import {
  resolveSenderAvatar,
  senderAvatarPrimarySourceSchemaValues,
} from '../../lib/sender-avatar';
import { userSettingsSchema } from '../../lib/schemas';
import { getZeroDB } from '../../lib/server-utils';
import { activeConnectionProcedure, router } from '../trpc';
import { z } from 'zod';

export const avatarRouter = router({
  getByEmail: activeConnectionProcedure
    .input(
      z.object({
        email: z.string().email(),
        name: z.string().trim().optional(),
      }),
    )
    .output(
      z.object({
        email: z.string().email(),
        domain: z.string(),
        primary: z
          .object({
            source: z.enum(senderAvatarPrimarySourceSchemaValues),
            url: z.string().nullable(),
            svgContent: z.string().nullable(),
          })
          .nullable(),
        fallbackUrls: z.array(z.string()),
      }),
    )
    .query(async ({ ctx, input }) => {
      const googleAuth =
        ctx.activeConnection.providerId === 'google'
          ? {
              accessToken: ctx.activeConnection.accessToken,
              refreshToken: ctx.activeConnection.refreshToken,
              scope: ctx.activeConnection.scope,
            }
          : null;

      // Privacy gate (B-015): honor the user's `externalImages` setting. When disabled,
      // resolveSenderAvatar skips all anonymous third-party image hosts (Gravatar,
      // Clearbit, icon.horse, DuckDuckGo, favicon scraping, BIMI) so the sender's email
      // and domain never leak to them. Defaults to true (matching defaultUserSettings)
      // on any settings-load/parse failure to preserve existing behavior.
      let externalImages = true;
      try {
        const db = await getZeroDB(ctx.sessionUser.id);
        const result = await db.findUserSettings();
        if (result) {
          const parsed = userSettingsSchema.safeParse(result.settings);
          if (parsed.success) {
            externalImages = parsed.data.externalImages;
          }
        }
      } catch (error) {
        console.warn('[avatar] Failed to load externalImages setting; defaulting to true', error);
      }

      return resolveSenderAvatar({
        email: input.email,
        name: input.name,
        googleAuth,
        externalImages,
      });
    }),
});
