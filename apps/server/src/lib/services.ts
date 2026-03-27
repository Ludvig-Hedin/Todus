import { env } from '../env';
import { Redis } from '@upstash/redis';
import { Resend } from 'resend';

export const resend = () => {
  if (!env.RESEND_API_KEY) {
    console.error('[RESEND] RESEND_API_KEY is NOT set — emails will NOT be sent');
    return {
      emails: {
        send: async (..._args: unknown[]) => {
          // Do not log args — they may contain PII (recipient email, OTP codes)
          console.error('[RESEND:MOCK] Email send called but RESEND_API_KEY is missing');
          throw new Error('Email sending is not configured — RESEND_API_KEY is missing');
        },
      },
    };
  }
  return new Resend(env.RESEND_API_KEY);
};

export const redis = () => new Redis({ url: env.REDIS_URL, token: env.REDIS_TOKEN });

export const twilio = () => {
  // Return a mock for local development when Twilio is not fully configured
  if (env.NODE_ENV === 'local' || (env.NODE_ENV === 'development' && !env.TWILIO_PHONE_NUMBER)) {
    return {
      messages: {
        send: async (to: string, body: string) =>
          console.log(`[TWILIO:MOCK] Sending message to ${to}: ${body}`),
      },
    };
  }

  if (!env.TWILIO_ACCOUNT_SID || !env.TWILIO_AUTH_TOKEN || !env.TWILIO_PHONE_NUMBER) {
    console.warn('Twilio is not configured correctly. SMS features will not work.');
    return {
      messages: {
        send: async (to: string, body: string) =>
          console.warn(`[TWILIO:MISSING_CONFIG] Would send message to ${to}: ${body}`),
      },
    };
  }

  const send = async (to: string, body: string) => {
    const response = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/Messages.json`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Authorization: `Basic ${btoa(`${env.TWILIO_ACCOUNT_SID}:${env.TWILIO_AUTH_TOKEN}`)}`,
        },
        body: new URLSearchParams({
          To: to,
          From: env.TWILIO_PHONE_NUMBER,
          Body: body,
        }),
      },
    );

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Failed to send OTP: ${error}`);
    }
  };

  return {
    messages: {
      send,
    },
  };
};
