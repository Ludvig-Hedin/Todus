import {
  AIWritingAssistantEmail,
  AutoLabelingEmail,
  CategoriesEmail,
  ShortcutsEmail,
  SuperSearchEmail,
  TodusProEmail,
  WelcomeEmail,
} from './react-emails/email-sequences';
import { createAuthMiddleware, phoneNumber, jwt, bearer, mcp, emailOTP } from 'better-auth/plugins';
import { account as accountTable, marketingEmailDelivery } from '../db/schema';
import { type Account, betterAuth, type BetterAuthOptions } from 'better-auth';
import { getBrowserTimezone, isValidTimezone } from './timezones';
import { drizzleAdapter } from 'better-auth/adapters/drizzle';
import { getSocialProviders } from './auth-providers';
import { redis, resend, twilio } from './services';
import { dubAnalytics } from '@dub/better-auth';
import { defaultUserSettings } from './schemas';
import { disableBrainFunction } from './brain';
import { APIError } from 'better-auth/api';
import { getZeroDB } from './server-utils';
import { type EProviders } from '../types';
import { createDriver } from './driver';
import type { ReactNode } from 'react';
import { Autumn } from 'autumn-js';
import { eq } from 'drizzle-orm';
import { createDb } from '../db';
import { env } from '../env';
import { Dub } from 'dub';

const ONBOARDING_CAMPAIGN_KEY = 'onboarding_v1';

const normalizeRecipientEmail = (email: string) => email.trim().toLowerCase();
const maskEmail = (email: string) => {
  const normalized = normalizeRecipientEmail(email);
  const [localPart = '', domain = ''] = normalized.split('@');
  const localPrefix = localPart ? `${localPart[0]}***` : '***';
  return domain ? `${localPrefix}@${domain}` : localPrefix;
};

const campaignSendDay = (date: Date) => date.toISOString().slice(0, 10);

const extractResendId = (result: unknown) => {
  if (!result || typeof result !== 'object') return null;
  const data = 'data' in result ? result.data : undefined;
  if (!data || typeof data !== 'object') return null;
  return 'id' in data && typeof data.id === 'string' ? data.id : null;
};

const scheduleCampaign = async (userInfo: { userId: string; address: string; name: string }) => {
  const name = userInfo.name || 'there';
  const resendService = resend();
  const { db, conn } = createDb(env.HYPERDRIVE.connectionString);

  const emails = [
    {
      key: 'welcome',
      subject: 'Welcome to Todus',
      react: WelcomeEmail({ name }) as ReactNode,
      delayDays: 0,
    },
    {
      key: 'todus_pro',
      subject: 'Todus Pro is here',
      react: TodusProEmail({ name }) as ReactNode,
      delayDays: 1,
    },
    {
      key: 'auto_labeling',
      subject: 'Auto-labeling is here 🎉📥',
      react: AutoLabelingEmail({ name }) as ReactNode,
      delayDays: 2,
    },
    {
      key: 'ai_writing_assistant',
      subject: 'AI Writing Assistant is here 🤖💬',
      react: AIWritingAssistantEmail({ name }) as ReactNode,
      delayDays: 3,
    },
    {
      key: 'shortcuts',
      subject: 'Shortcuts are here 🔧🚀',
      react: ShortcutsEmail({ name }) as ReactNode,
      delayDays: 4,
    },
    {
      key: 'categories',
      subject: 'Categories are here 📂🔍',
      react: CategoriesEmail({ name }) as ReactNode,
      delayDays: 5,
    },
    {
      key: 'super_search',
      subject: 'Super Search is here 🔍🚀',
      react: SuperSearchEmail({ name }) as ReactNode,
      delayDays: 6,
    },
  ];

  const normalizedEmail = normalizeRecipientEmail(userInfo.address);
  const maskedEmail = maskEmail(userInfo.address);
  const baseTime = Date.now();

  try {
    await Promise.allSettled(
      emails.map(async (email) => {
        const scheduledFor = new Date(baseTime + email.delayDays * 24 * 60 * 60 * 1000);
        const sendOnDate = campaignSendDay(scheduledFor);

        const [reservation] = await db
          .insert(marketingEmailDelivery)
          .values({
            id: crypto.randomUUID(),
            userId: userInfo.userId,
            campaign: ONBOARDING_CAMPAIGN_KEY,
            emailKey: email.key,
            subject: email.subject,
            recipientEmail: userInfo.address,
            recipientEmailNormalized: normalizedEmail,
            sendOnDate,
            scheduledFor,
          })
          .onConflictDoNothing()
          .returning({ id: marketingEmailDelivery.id });

        if (!reservation) {
          console.log('[CAMPAIGN] Skipping duplicate marketing email enrollment', {
            recipientEmail: maskedEmail,
            subject: email.subject,
            sendOnDate,
          });
          return;
        }

        try {
          const result = await resendService.emails.send(
            {
              from: 'Todus <onboarding@todus.app>',
              to: userInfo.address,
              subject: email.subject,
              react: email.react as Parameters<typeof resendService.emails.send>[0]['react'],
              ...(email.delayDays > 0 ? { scheduledAt: scheduledFor.toISOString() } : {}),
            },
            {
              idempotencyKey: `onboarding:${normalizedEmail}:${email.key}:${sendOnDate}`,
            },
          );

          await db
            .update(marketingEmailDelivery)
            .set({
              resendId: extractResendId(result),
              sentAt: new Date(),
            })
            .where(eq(marketingEmailDelivery.id, reservation.id));
        } catch (error) {
          await db
            .delete(marketingEmailDelivery)
            .where(eq(marketingEmailDelivery.id, reservation.id));
          console.error('[CAMPAIGN] Failed to send onboarding email', {
            to: maskedEmail,
            subject: email.subject,
            error,
          });
        }
      }),
    );
  } finally {
    await conn.end();
  }
};

const parseJwtPayload = (
  token: string | null | undefined,
): { email?: string; name?: string; picture?: string } | undefined => {
  if (!token) return undefined;
  const parts = token.split('.');
  if (parts.length < 2) return undefined;

  try {
    const payload = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = payload.padEnd(Math.ceil(payload.length / 4) * 4, '=');
    const parsed = JSON.parse(Buffer.from(padded, 'base64').toString('utf8')) as {
      email?: string;
      name?: string;
      picture?: string;
    };
    return parsed;
  } catch {
    return undefined;
  }
};

/**
 * Resolves the identity of the mailbox represented by the OAuth account row.
 *
 * Important: this must describe the connected provider account, not the Todus
 * app user. Users can connect multiple Google/Microsoft mailboxes, so reading
 * `mail0_user.email` here would incorrectly collapse those accounts together.
 */
const resolveAccountIdentity = async (
  account: Account,
): Promise<{ address: string; name: string; photo: string } | undefined> => {
  if (account.providerId === 'google') {
    const idTokenPayload = parseJwtPayload(account.idToken);
    if (idTokenPayload?.email) {
      return {
        address: idTokenPayload.email,
        name: idTokenPayload.name || 'Unknown',
        photo: idTokenPayload.picture || '',
      };
    }

    if (account.accessToken) {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000);
      try {
        const res = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
          headers: { Authorization: `Bearer ${account.accessToken}` },
          signal: controller.signal,
        });
        clearTimeout(timeoutId);
        if (res.ok) {
          const data = (await res.json()) as {
            email?: string;
            name?: string;
            picture?: string;
          };
          if (data.email) {
            return {
              address: data.email,
              name: data.name || 'Unknown',
              photo: data.picture || '',
            };
          }
        } else {
          const body = await res.text().catch(() => '');
          console.error('[resolveAccountIdentity] Google OIDC userinfo non-OK', {
            userId: account.userId,
            status: res.status,
            body: body.slice(0, 200),
          });
        }
      } catch (error) {
        clearTimeout(timeoutId);
        console.error('[resolveAccountIdentity] Google OIDC userinfo fetch failed', {
          userId: account.userId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    return undefined;
  }

  if (account.accessToken) {
    try {
      const driver = createDriver(account.providerId, {
        auth: {
          accessToken: account.accessToken,
          refreshToken: account.refreshToken ?? '',
          userId: account.userId,
          email: '',
        },
      });
      const userInfo = await driver.getUserInfo();
      if (userInfo.address) {
        return {
          address: userInfo.address,
          name: userInfo.name || 'Unknown',
          photo: userInfo.photo || '',
        };
      }
    } catch (error) {
      console.error('[resolveAccountIdentity] driver getUserInfo failed', {
        userId: account.userId,
        provider: account.providerId,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return undefined;
};

const syncConnectionFromAccount = async (
  account: Account,
  options: { scheduleOnboardingCampaign: boolean },
) => {
  // Apple is an identity-only provider (used for authentication via native
  // Sign in with Apple). It doesn't grant email access tokens like Google does,
  // so we skip the connection setup which requires OAuth access/refresh tokens.
  if (account.providerId === 'apple') {
    return;
  }

  // Sign-in MUST NOT fail if connection setup fails. Better-Auth runs this hook
  // as `account.create.after` / `account.update.after` during the OAuth callback.
  // Any exception (or thrown Response redirect) propagates out of the auth handler
  // and aborts the sign-in, leaving the user stuck on api.todus.app instead of
  // being redirected to `callbackURL` (web) or `todus://auth-callback` (native).
  // Connection errors are recoverable — the user can reconnect Gmail from settings.
  if (!account.accessToken) {
    console.error('[syncConnectionFromAccount] Missing access token', {
      userId: account.userId,
      provider: account.providerId,
    });
    return;
  }

  // Refresh tokens: Google only re-issues a refresh_token on initial consent
  // or when `prompt=consent` forces re-consent. On silent re-auth (e.g. the
  // user clicking a second OAuth flow for the same Google account) Google can
  // omit the refresh_token, and Better Auth will persist `null` onto the
  // account row. We fall back to:
  //   1. The refresh_token stored on the existing account row (if any).
  //   2. The refresh_token stored on the existing connection row (if any) —
  //      still works even if Better Auth cleared the account row.
  let resolvedRefreshToken: string | null = account.refreshToken ?? null;
  if (!resolvedRefreshToken) {
    try {
      const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
      try {
        const [existingAccount] = await db
          .select({ refreshToken: accountTable.refreshToken })
          .from(accountTable)
          .where(eq(accountTable.id, account.id))
          .limit(1);
        resolvedRefreshToken = existingAccount?.refreshToken ?? null;
      } finally {
        await conn.end();
      }
    } catch (error) {
      console.error('[syncConnectionFromAccount] account refresh-token lookup failed', {
        userId: account.userId,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  const identity = await resolveAccountIdentity(account);
  if (!identity?.address) {
    console.error('[syncConnectionFromAccount] Could not resolve user email', {
      userId: account.userId,
      provider: account.providerId,
    });
    return;
  }

  // Preserve an existing connection's refresh_token if the current OAuth
  // round-trip didn't re-issue one. This is the common "user re-authenticated
  // without re-consent" path — without this, the stored refresh_token would
  // get wiped out and subsequent API calls would fail with 401.
  if (!resolvedRefreshToken) {
    try {
      const db = await getZeroDB(account.userId);
      const existing = await db.findManyConnections();
      const match = existing.find(
        (c) => c.providerId === account.providerId && c.email === identity.address,
      );
      if (match?.refreshToken) {
        resolvedRefreshToken = match.refreshToken;
      }
    } catch (error) {
      console.error('[syncConnectionFromAccount] existing-connection refresh-token lookup failed', {
        userId: account.userId,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  if (!resolvedRefreshToken) {
    console.error(
      '[syncConnectionFromAccount] No refresh token available (neither account nor prior connection)',
      {
        userId: account.userId,
        provider: account.providerId,
      },
    );
    return;
  }

  // Keep the stored `scope` aligned with what the driver expects to use so
  // downstream code can assume scope consistency. `getScope()` is constant.
  const driver = createDriver(account.providerId, {
    auth: {
      accessToken: account.accessToken,
      refreshToken: resolvedRefreshToken,
      userId: account.userId,
      email: identity.address,
    },
  });

  const updatingInfo = {
    name: identity.name || 'Unknown',
    picture: identity.photo || '',
    accessToken: account.accessToken,
    refreshToken: resolvedRefreshToken,
    scope: driver.getScope(),
    expiresAt: account.accessTokenExpiresAt ?? new Date(Date.now() + 3600000),
  };
  // `userInfo` kept for the downstream scheduleCampaign call signature.
  const userInfo = { address: identity.address, name: identity.name, photo: identity.photo };

  let result: { id: string } | undefined;
  try {
    const db = await getZeroDB(account.userId);
    const created = await db.createConnection(
      account.providerId as EProviders,
      userInfo.address,
      updatingInfo,
    );
    result = created[0];

    const settingsRow = await db.findUserSettings();
    const currentSettings = settingsRow?.settings ?? defaultUserSettings;
    const shouldScheduleCampaign =
      options.scheduleOnboardingCampaign && !currentSettings.welcomeEmailSent;

    if (shouldScheduleCampaign) {
      await db.updateUserSettings({
        ...currentSettings,
        welcomeEmailSent: true,
      });

      if (env.NODE_ENV === 'production') {
        await scheduleCampaign({
          userId: account.userId,
          address: userInfo.address,
          name: userInfo.name || 'there',
        });
      }
    }
  } catch (error) {
    console.error('[syncConnectionFromAccount] Failed to persist connection', {
      userId: account.userId,
      provider: account.providerId,
      error: error instanceof Error ? error.message : String(error),
    });
    return;
  }

  if (result && env.GOOGLE_S_ACCOUNT && env.GOOGLE_S_ACCOUNT !== '{}') {
    try {
      await env.subscribe_queue.send({
        connectionId: result.id,
        providerId: account.providerId,
      });
    } catch (error) {
      console.error('[syncConnectionFromAccount] Failed to enqueue subscribe job', {
        connectionId: result.id,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
};

// Better-Auth runs these as fire-and-forget `after` hooks during the OAuth
// callback. Wrapping the inner call in try/catch is belt-and-suspenders —
// `syncConnectionFromAccount` is already non-throwing, but we defend against
// any future regression that could re-introduce an exception and break
// sign-in (landing the user on api.todus.app instead of their callbackURL).
const accountCreateHook = async (account: Account) => {
  try {
    await syncConnectionFromAccount(account, { scheduleOnboardingCampaign: true });
  } catch (error) {
    console.error('[accountCreateHook] unexpected error', error);
  }
};

const accountUpdateHook = async (account: Account) => {
  try {
    await syncConnectionFromAccount(account, { scheduleOnboardingCampaign: false });
  } catch (error) {
    console.error('[accountUpdateHook] unexpected error', error);
  }
};

export const createAuth = () => {
  const twilioClient = twilio();

  // Only enable Dub analytics if API key is configured — without it, the
  // dubAnalytics plugin throws during social sign-in and causes 500 errors
  const dubPlugins = env.DUB_API_KEY ? [dubAnalytics({ dubClient: new Dub() })] : [];

  return betterAuth({
    plugins: [
      ...dubPlugins,
      mcp({
        loginPage: env.VITE_PUBLIC_APP_URL + '/login',
      }),
      jwt({
        // Short-lived JWT as "access token" for native apps (15 minutes).
        // Native apps also receive a long-lived raw session token as "refresh token".
        // `expiresIn` keeps that session valid for up to 90 days, while `updateAge`
        // controls how frequently the sliding session window is refreshed (currently 1 day).
        // When the JWT expires, the native app calls /auth/refresh-native-token with the
        // session token to get a fresh JWT.
        jwt: { expirationTime: '15m' },
      }),
      bearer(),
      phoneNumber({
        sendOTP: async ({ code, phoneNumber }) => {
          await twilioClient.messages
            .send(phoneNumber, `Your verification code is: ${code}, do not share it with anyone.`)
            .catch((error) => {
              console.error('Failed to send OTP', error);
              throw new APIError('INTERNAL_SERVER_ERROR', {
                message: `Failed to send OTP, ${error.message}`,
              });
            });
        },
      }),
      // Email OTP — sends a 6-digit code via Resend for native app sign-in.
      // Endpoints: POST /api/auth/email-otp/send-verification-otp, POST /api/auth/sign-in/email-otp
      emailOTP({
        otpLength: 6,
        expiresIn: 300, // 5 minutes
        sendVerificationOTP: async ({ email, otp, type }) => {
          const maskedEmail = maskEmail(email);
          console.log(
            `[EMAIL_OTP] Sending OTP to ${maskedEmail}, type=${type}, code length=${otp.length}`,
          );
          const resendClient = resend();
          const otpHtml = `
            <div style="font-family: system-ui, -apple-system, sans-serif; max-width: 400px; margin: 0 auto; padding: 40px 20px;">
              <h2 style="font-size: 24px; font-weight: 600; margin-bottom: 8px;">Your verification code</h2>
              <p style="color: #666; margin-bottom: 24px;">Enter this code in the Todus app to ${type === 'sign-in' ? 'sign in' : 'verify your email'}.</p>
              <div style="background: #f5f5f5; border-radius: 12px; padding: 20px; text-align: center; font-size: 32px; font-weight: 700; letter-spacing: 8px; font-family: monospace;">${otp}</div>
              <p style="color: #999; font-size: 13px; margin-top: 24px;">This code expires in 5 minutes. If you didn't request this, you can safely ignore it.</p>
            </div>
          `;

          // Try primary sender (todus.app domain) first
          try {
            const result = await resendClient.emails.send({
              from: 'Todus <onboarding@todus.app>',
              to: email,
              subject: 'Your Todus verification code',
              html: otpHtml,
            });
            console.log(
              `[EMAIL_OTP] Email sent successfully via todus.app to ${maskedEmail}`,
              JSON.stringify(result),
            );
            return;
          } catch (primaryError) {
            const msg = primaryError instanceof Error ? primaryError.message : String(primaryError);
            // Fall through to test domain if todus.app domain is not yet verified
            console.warn(
              `[EMAIL_OTP] Primary sender failed (todus.app), attempting fallback. Error: ${msg}`,
            );
          }

          const canUseDevFallback =
            env.NODE_ENV !== 'production' && email.toLowerCase() === 'ludvighedin15@gmail.com';

          if (!canUseDevFallback) {
            throw new APIError('INTERNAL_SERVER_ERROR', {
              message: 'Failed to send verification email from the verified sender.',
            });
          }

          // Fallback: use Resend's test domain only for the owner mailbox during local/dev
          // verification. Resend blocks arbitrary recipients on resend.dev.
          try {
            const result = await resendClient.emails.send({
              from: 'Todus <onboarding@resend.dev>',
              to: email,
              subject: 'Your Todus verification code',
              html: otpHtml,
            });
            console.log(
              `[EMAIL_OTP] Email sent via resend.dev fallback to ${maskedEmail}`,
              JSON.stringify(result),
            );
          } catch (fallbackError) {
            const msg =
              fallbackError instanceof Error ? fallbackError.message : String(fallbackError);
            console.error(
              `[EMAIL_OTP] Both senders failed for ${maskedEmail}. Fallback error: ${msg}`,
            );
            throw new APIError('INTERNAL_SERVER_ERROR', {
              message: 'Failed to send verification email. Please try again later.',
            });
          }
        },
      }),
    ],
    user: {
      deleteUser: {
        enabled: true,
        async sendDeleteAccountVerification(data) {
          const verificationUrl = data.url;

          await resend().emails.send({
            from: 'Todus <no-reply@todus.app>',
            to: data.user.email,
            subject: 'Delete your Todus account',
            html: `
            <h2>Delete Your Todus Account</h2>
            <p>Click the link below to delete your account:</p>
            <a href="${verificationUrl}">${verificationUrl}</a>
          `,
          });
        },
        beforeDelete: async (user, request) => {
          if (!request) throw new APIError('BAD_REQUEST', { message: 'Request object is missing' });
          const db = await getZeroDB(user.id);
          const connections = await db.findManyConnections();
          const autumn = new Autumn({ secretKey: env.AUTUMN_SECRET_KEY });
          try {
            const result = await autumn.customers.delete(user.id);
            if (!result.data && result.statusCode !== 404) {
              console.error('Failed to delete Autumn customer:', {
                statusCode: result.statusCode ?? null,
                code: result.error?.code ?? null,
                message: result.error?.message ?? null,
              });
            }
          } catch (error) {
            console.error('Failed to delete Autumn customer:', error);
            // Continue with deletion process despite Autumn failure
          }

          const revokedAccounts = (
            await Promise.allSettled(
              connections.map(async (connection) => {
                if (!connection.accessToken || !connection.refreshToken) return false;
                await disableBrainFunction({
                  id: connection.id,
                  providerId: connection.providerId as EProviders,
                });
                const driver = createDriver(connection.providerId, {
                  auth: {
                    accessToken: connection.accessToken,
                    refreshToken: connection.refreshToken,
                    userId: user.id,
                    email: connection.email,
                  },
                });
                const token = connection.refreshToken;
                return await driver.revokeToken(token || '');
              }),
            )
          ).map((result) => {
            if (result.status === 'fulfilled') {
              return result.value;
            }
            return false;
          });

          if (revokedAccounts.every((value) => !!value)) {
            console.log('Failed to revoke some accounts');
          }

          await db.deleteUser();
        },
      },
    },
    databaseHooks: {
      account: {
        create: {
          after: accountCreateHook,
        },
        update: {
          after: accountUpdateHook,
        },
      },
    },
    emailAndPassword: {
      enabled: true,
      requireEmailVerification: true,
      sendResetPassword: async ({ user, url }) => {
        await resend().emails.send({
          from: 'Todus <onboarding@todus.app>',
          to: user.email,
          subject: 'Reset your password',
          html: `
            <h2>Reset Your Password</h2>
            <p>Click the link below to reset your password:</p>
            <a href="${url}">${url}</a>
            <p>If you didn't request this, you can safely ignore this email.</p>
          `,
        });
      },
    },
    emailVerification: {
      sendOnSignUp: false,
      autoSignInAfterVerification: true,
      sendVerificationEmail: async ({ user, token }) => {
        const verificationUrl = `${env.VITE_PUBLIC_APP_URL}/api/auth/verify-email?token=${token}&callbackURL=/settings/connections`;

        await resend().emails.send({
          from: 'Todus <onboarding@todus.app>',
          to: user.email,
          subject: 'Verify your Todus account',
          html: `
            <h2>Verify Your Todus Account</h2>
            <p>Click the link below to verify your email:</p>
            <a href="${verificationUrl}">${verificationUrl}</a>
          `,
        });
      },
    },
    hooks: {
      after: createAuthMiddleware(async (ctx) => {
        // all hooks that run on sign-up routes
        if (ctx.path.startsWith('/sign-up')) {
          // only true if this request is from a new user
          const newSession = ctx.context.newSession;
          if (newSession) {
            // Check if user already has settings
            const db = await getZeroDB(newSession.user.id);
            const existingSettings = await db.findUserSettings();

            if (!existingSettings) {
              // get timezone from vercel's header
              const headerTimezone = ctx.headers?.get('x-vercel-ip-timezone');
              // validate timezone from header or fallback to browser timezone
              const timezone =
                headerTimezone && isValidTimezone(headerTimezone)
                  ? headerTimezone
                  : getBrowserTimezone();
              // write default settings against the user
              await db.insertUserSettings({
                ...defaultUserSettings,
                timezone,
              });
            }

            // Provision an Autumn customer and attach the free plan so plan UI
            // and `ai_usage` credits resolve from day one. Each call is wrapped
            // independently — a failure here must never block sign-up.
            const autumn = new Autumn({ secretKey: env.AUTUMN_SECRET_KEY });
            try {
              const result = await autumn.customers.create({
                id: newSession.user.id,
                name: newSession.user.name,
                email: newSession.user.email,
              });
              if (!result.data && result.statusCode !== 409) {
                console.error('[signup] Autumn customers.create failed', {
                  statusCode: result.statusCode ?? null,
                  code: result.error?.code ?? null,
                  message: result.error?.message ?? null,
                });
              }
            } catch (error) {
              console.error('[signup] Autumn customers.create failed', error);
            }
            try {
              const result = await autumn.attach({
                customer_id: newSession.user.id,
                product_id: 'free',
              });
              if (!result.data && result.statusCode !== 409) {
                console.error('[signup] Autumn attach free product failed', {
                  statusCode: result.statusCode ?? null,
                  code: result.error?.code ?? null,
                  message: result.error?.message ?? null,
                });
              }
            } catch (error) {
              console.error('[signup] Autumn attach free product failed', error);
            }
            // Hydrate cached subscription columns on the user row from Autumn.
            try {
              const { refreshSubscriptionCache } = await import('./billing');
              await refreshSubscriptionCache(newSession.user.id);
            } catch (error) {
              console.error('[signup] subscription cache hydration failed', error);
            }
          }
        }
      }),
    },
    ...createAuthConfig(),
  });
};

const createAuthConfig = () => {
  const cache = redis();
  const { db } = createDb(env.HYPERDRIVE.connectionString);
  const toOrigin = (input: string) => {
    try {
      return new URL(input).origin;
    } catch {
      return input;
    }
  };
  const trustedOrigins = Array.from(
    new Set(
      [
        'https://app.todus.app',
        'https://api.todus.app',
        'https://todus.app',
        'https://todus.app',
        'https://todus-production.ludvighedin15.workers.dev',
        'https://todus-server-v1-production.ludvighedin15.workers.dev',
        'https://zero-server-v1-production.ludvighedin15.workers.dev',
        'http://localhost:3000',
        'http://localhost:8787',
        toOrigin(env.VITE_PUBLIC_APP_URL),
        toOrigin(env.VITE_PUBLIC_BACKEND_URL),
        'todus://auth-callback',
        'todus://link-callback',
        // Required for Apple Sign-in ID token validation flows
        'https://appleid.apple.com',
      ].filter(Boolean),
    ),
  );

  return {
    database: drizzleAdapter(db, { provider: 'pg' }),
    secondaryStorage: {
      get: async (key: string) => {
        try {
          const value = await cache.get(key);
          return typeof value === 'string' ? value : value ? JSON.stringify(value) : null;
        } catch (err) {
          console.warn('Redis get error:', err);
          return null; // Fallback to database
        }
      },
      set: async (key: string, value: string, ttl?: number) => {
        try {
          if (ttl) await cache.set(key, value, { ex: ttl });
          else await cache.set(key, value);
        } catch (err) {
          console.warn('Redis set error:', err);
        }
      },
      delete: async (key: string) => {
        try {
          await cache.del(key);
        } catch (err) {
          console.warn('Redis del error:', err);
        }
      },
    },
    advanced: {
      ipAddress: {
        disableIpTracking: true,
      },
      cookiePrefix: env.NODE_ENV === 'development' ? 'better-auth-dev' : 'better-auth',
      crossSubDomainCookies: {
        enabled: true,
        domain: env.COOKIE_DOMAIN,
      },
    },
    baseURL: env.VITE_PUBLIC_BACKEND_URL,
    trustedOrigins,
    session: {
      cookieCache: {
        enabled: true,
        maxAge: 60 * 60 * 24 * 90, // 90 days — matches session lifetime
      },
      // 90-day rolling sessions: comparable to Gmail, Twitter, Facebook.
      // Combined with updateAge (1 day), the session extends every day the
      // user is active — so they stay logged in indefinitely as long as
      // they open the app within any 90-day window.
      expiresIn: 60 * 60 * 24 * 90, // 90 days
      updateAge: 60 * 60 * 24 * 1, // 1 day — extend session daily on activity
    },
    socialProviders: getSocialProviders(env as unknown as Record<string, string>),
    account: {
      accountLinking: {
        enabled: true,
        allowDifferentEmails: true,
        trustedProviders: ['google', 'microsoft', 'apple'],
      },
    },
    onAPIError: {
      onError: (error) => {
        console.error('API Error', error);
      },
      errorURL: `${env.VITE_PUBLIC_APP_URL}/login`,
      throw: true,
    },
  } satisfies BetterAuthOptions;
};

export const createSimpleAuth = () => {
  return betterAuth(createAuthConfig());
};

export type Auth = ReturnType<typeof createAuth>;
export type SimpleAuth = ReturnType<typeof createSimpleAuth>;
