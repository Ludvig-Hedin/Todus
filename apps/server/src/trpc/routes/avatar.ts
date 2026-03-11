import {
  resolveSenderAvatar,
  senderAvatarPrimarySourceSchemaValues,
} from '../../lib/sender-avatar';
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

      return resolveSenderAvatar({
        email: input.email,
        name: input.name,
        googleAuth,
      });
    }),
});
