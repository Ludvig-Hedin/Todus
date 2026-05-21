import { publicProcedure, router } from '../trpc';
import { resend } from '../../lib/services';
import { TRPCError } from '@trpc/server';
import { z } from 'zod';

export const contactRouter = router({
  submit: publicProcedure
    .input(
      z.object({
        firstName: z.string().min(1).max(50).trim(),
        lastName: z.string().min(1).max(50).trim(),
        email: z.string().email().max(200).trim(),
        phone: z.string().max(30).trim().optional(),
        message: z.string().min(10).max(2000).trim(),
        honeypot: z.string().max(0),
        loadTime: z.number().int().positive(),
      }),
    )
    .mutation(async ({ input }) => {
      // Bot check: honeypot field must be empty
      if (input.honeypot.length > 0) {
        return { success: true };
      }

      // Timing check: genuine users take >3 seconds to fill out a form
      const elapsed = Date.now() - input.loadTime;
      if (elapsed < 3000) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: 'Submission too fast. Please try again.',
        });
      }

      const r = resend();
      await r.emails.send({
        from: 'Todus <onboarding@todus.app>',
        to: ['founders@todus.app'],
        replyTo: input.email,
        subject: `Contact: ${input.firstName} ${input.lastName}`,
        html: `
          <h2 style="font-family:sans-serif;font-size:18px;margin-bottom:16px">New Contact Form Submission</h2>
          <table style="font-family:sans-serif;font-size:14px;border-collapse:collapse">
            <tr><td style="padding:4px 12px 4px 0;color:#666;font-weight:500">Name</td><td>${input.firstName} ${input.lastName}</td></tr>
            <tr><td style="padding:4px 12px 4px 0;color:#666;font-weight:500">Email</td><td><a href="mailto:${input.email}">${input.email}</a></td></tr>
            ${input.phone ? `<tr><td style="padding:4px 12px 4px 0;color:#666;font-weight:500">Phone</td><td>${input.phone}</td></tr>` : ''}
          </table>
          <hr style="margin:16px 0;border:none;border-top:1px solid #eee" />
          <p style="font-family:sans-serif;font-size:14px;color:#666;margin-bottom:8px;font-weight:500">Message</p>
          <p style="font-family:sans-serif;font-size:14px;white-space:pre-wrap">${input.message.replace(/</g, '&lt;').replace(/>/g, '&gt;')}</p>
        `,
      });

      return { success: true };
    }),
});
