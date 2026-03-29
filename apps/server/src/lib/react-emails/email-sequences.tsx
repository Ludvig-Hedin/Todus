// @ts-nocheck
import React from 'react';
import {
  Html,
  Head,
  Body,
  Container,
  Section,
  Text,
  Link,
  Preview,
  Heading,
} from '@react-email/components';

// Common styles
const main = {
  backgroundColor: '#ffffff',
  fontFamily: '"Helvetica Neue",Helvetica,Arial,sans-serif',
};

const container = {
  margin: '0',
  padding: '20px 0 48px',
  maxWidth: '560px',
};

const section = {
  padding: '0 24px',
};

const h1 = {
  color: '#333',
  fontSize: '24px',
  fontWeight: '600',
  lineHeight: '1.3',
  margin: '0 0 20px',
};

const text = {
  color: '#333',
  fontSize: '16px',
  lineHeight: '1.6',
  margin: '0 0 16px',
};

const listItem = {
  color: '#333',
  fontSize: '16px',
  lineHeight: '1.6',
  margin: '0 0 8px',
  paddingLeft: '12px',
};

const link = {
  color: '#007ee6',
  textDecoration: 'underline',
};

const signature = {
  color: '#333',
  fontSize: '16px',
  lineHeight: '1.6',
  margin: '20px 0 0',
  fontWeight: '500',
};

interface EmailProps {
  name?: string;
}

// 1. Welcome Email (On Signup)
export const WelcomeEmail = ({ name }: EmailProps) => {
  return (
    <Html>
      <Head />
      <Preview>Welcome to Todus — your inbox, calendar, tasks, and AI assistant</Preview>
      <Body style={main}>
        <Container style={container}>
          <Section style={section}>
        <Heading style={h1}>Welcome to Todus</Heading>
            <Text style={text}>Hey {name ? name : 'there'},</Text>
            <Text style={text}>
              I'm Ludvig, founder of Todus. You now have a workspace that spans email, calendar, tasks, and the AI assistant chat.
            </Text>
            <Text style={text}>
              If you've ever lost a thread, missed a meeting, or let a task fall through the cracks, this is for you.
            </Text>
            <Text style={text}>Todus is built different:</Text>
            <Text style={listItem}>• AI assistant that drafts replies, summarizes threads, and connects email, calendar, and tasks</Text>
            <Text style={listItem}>• Unified inbox, calendar, and task list so nothing disappears out of sight</Text>
            <Text style={listItem}>• Automatic labeling, shortcuts, and super search to keep you in flow</Text>
            <Text style={listItem}>• Privacy-first, open-source tooling that stays focused on your time</Text>
            <Text style={text}>
              It's still early, but this playground is real. And it is yours to explore.
            </Text>
            <Text style={text}>
              Ready to chat about email, calendar, or the AI roadmap?{' '}
              <Link href="https://cal.com/ludvig-hedin-iouaiw" style={link}>
                Book a short call
              </Link>
            </Text>
            <Text style={text}>
              Thanks for joining the Todus community.
            </Text>
            <Text style={signature}>Ludvig</Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
};

// 2. Todus Pro (1 Day After Signup)
export const TodusProEmail = ({ name }: EmailProps) => {
  return (
    <Html>
      <Head />
      <Preview>Todus Pro unlocks your unified workspace</Preview>
      <Body style={main}>
        <Container style={container}>
          <Section style={section}>
        <Heading style={h1}>Todus Pro is here</Heading>
            <Text style={text}>Hey {name ? name : 'there'},</Text>
            <Text style={text}>
              Your workspace just got a serious upgrade.
            </Text>
            <Text style={text}>
              Todus Pro brings unlimited email, calendar, tasks, and AI assistance together so you never lose context.
            </Text>
            <Text style={text}>Here's what you get:</Text>
            <Text style={listItem}>Unlimited email, calendar, and task accounts</Text>
            <Text style={listItem}>AI assistant chat that summarizes, writes, and nudges you toward next steps</Text>
            <Text style={listItem}>Advanced task workflows, templates, and automations</Text>
            <Text style={listItem}>Priority inbox, calendar, and task triage</Text>
            <Text style={listItem}>Custom labels, shortcuts, and command palette macros</Text>
            <Text style={listItem}>Priority support and early access to new experiences</Text>
            <Text style={listItem}>Flexible pricing with an annual option</Text>
            <Text style={text}>
              It's the full Todus workspace — email, calendar, tasks, and AI — unlocked for people who want to move with flow.
            </Text>
            <Text style={text}>
              <Link href="https://todus.app/pricing" style={link}>
                Try it free for 7 days, no strings attached
              </Link>
            </Text>
            <Text style={text}>
              Want to chat about Pro and the roadmap?{' '}
              <Link href="https://cal.com/ludvig-hedin-iouaiw" style={link}>
                Book a short call
              </Link>
            </Text>
            <Text style={text}>
              Let's make every part of your day smoother,
            </Text>
            <Text style={signature}>Ludvig</Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
};

// 3. Auto Labeling (2 Days After Signup)
export const AutoLabelingEmail = ({ name }: EmailProps) => {
  return (
    <Html>
      <Head />
      <Preview>Auto-labeling keeps your workspace organized</Preview>
      <Body style={main}>
        <Container style={container}>
          <Section style={section}>
        <Heading style={h1}>Auto-labeling keeps your workspace organized</Heading>
            <Text style={text}>Hey {name ? name : 'there'},</Text>
            <Text style={text}>
              Todus now labels your email, calendar, and task entries automatically so the most important things rise to the top.
            </Text>
            <Text style={text}>Here’s what it does:</Text>
            <Text style={listItem}>Sorts into categories like Newsletters, Receipts, Invites, Projects, and Tasks</Text>
            <Text style={listItem}>Learns from your behavior so it keeps improving</Text>
            <Text style={listItem}>Lets you rename or tweak labels from any device</Text>
            <Text style={text}>
              It keeps your inbox, calendar, and task list in sync without manual filters.
            </Text>
            <Text style={text}>
              Want me to walk you through how the AI assistant uses those labels to suggest next steps?{' '}
              <Link href="https://cal.com/ludvig-hedin-iouaiw" style={link}>
                Book a short call
              </Link>
            </Text>
            <Text style={text}>
              Thanks for being here,
            </Text>
            <Text style={signature}>Ludvig</Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
};

// 4. AI Writing Assistant (3 Days After Signup)
export const AIWritingAssistantEmail = ({ name }: EmailProps) => {
  return (
    <Html>
      <Head />
      <Preview>Write faster with the Todus AI assistant</Preview>
      <Body style={main}>
        <Container style={container}>
          <Section style={section}>
            <Heading style={h1}>Write faster with the AI assistant</Heading>
            <Text style={text}>Hey {name ? name : 'there'},</Text>
            <Text style={text}>
              Todus reads your email, calendar, and task context before it ever suggests a reply.
              That way it stays on brand with your voice and the right project context.
            </Text>
            <Text style={text}>Here's how it supports you:</Text>
            <Text style={listItem}>Reads each message and summaries the thread in seconds</Text>
            <Text style={listItem}>Suggests thoughtful replies, follow-ups, or action items</Text>
            <Text style={listItem}>Lets you tweak the tone, extend a task, or roll it into your calendar</Text>
            <Text style={text}>
              Try it next time you open an email: hit "Generate" and edit as you go.
            </Text>
            <Text style={text}>
              Want a quick walkthrough or to share feedback?{' '}
              <Link href="https://cal.com/ludvig-hedin-iouaiw" style={link}>
                Book a short call
              </Link>
            </Text>
            <Text style={text}>
              Talk soon,
            </Text>
            <Text style={signature}>Ludvig</Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
};

// 5. Shortcuts (4 Days After Signup)
export const ShortcutsEmail = ({ name }: EmailProps) => {
  return (
    <Html>
      <Head />
      <Preview>Fly through Todus with shortcuts</Preview>
      <Body style={main}>
        <Container style={container}>
          <Section style={section}>
            <Heading style={h1}>Fly through Todus with shortcuts</Heading>
            <Text style={text}>Hey {name ? name : 'there'},</Text>
            <Text style={text}>
              Keyboard shortcuts keep you off the mouse and in flow across email, calendar, tasks, and the AI assistant.
            </Text>
            <Text style={text}>Here are a few worth mastering:</Text>
            <Text style={listItem}>C to start a new email</Text>
            <Text style={listItem}>R to reply</Text>
            <Text style={listItem}>E to archive or file a thread</Text>
            <Text style={listItem}>V to open the voice or AI assistant</Text>
            <Text style={listItem}>Cmd + K to launch the command palette</Text>
            <Text style={listItem}>G + I to go to your inbox</Text>
            <Text style={listItem}>Cmd + T to jump to tasks and Cmd + M for meetings</Text>
            <Text style={text}>
              Every shortcut is customizable — hit ? in the app to view or remap them instantly.
            </Text>
            <Text style={text}>
              Have a shortcut idea or need help wiring a workflow?{' '}
              <Link href="https://cal.com/ludvig-hedin-iouaiw" style={link}>
                Book a short call
              </Link>
            </Text>
            <Text style={text}>
              Let's make Todus feel like an extension of how you already work.
            </Text>
            <Text style={signature}>Ludvig</Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
};

// 6. Categories (5 Days After Signup)
export const CategoriesEmail = ({ name }: EmailProps) => {
  return (
    <Html>
      <Head />
      <Preview>Inbox clarity is live in Todus</Preview>
      <Body style={main}>
        <Container style={container}>
          <Section style={section}>
            <Heading style={h1}>Inbox clarity is live in Todus</Heading>
            <Text style={text}>Hey {name ? name : 'there'},</Text>
            <Text style={text}>
              Todus now organizes your emails into smart categories right above your inbox, calendar, and tasks.
              No manual filters, no digging.
            </Text>
            <Text style={text}>Here is what you’ll see:</Text>
            <Text style={listItem}>Primary — real conversations and people who matter</Text>
            <Text style={listItem}>Alerts — security notices, invoices, and account updates</Text>
            <Text style={listItem}>Personal — family and friends</Text>
            <Text style={listItem}>Notifications — confirmations, reminders, and task nudges</Text>
            <Text style={listItem}>Promotions — newsletters, ads, and lower priority chatter</Text>
            <Text style={text}>
              Todus learns from what you open and complete so the categories get sharper over time.
            </Text>
            <Text style={text}>
              Want to customize categories or share a suggestion?{' '}
              <Link href="https://cal.com/ludvig-hedin-iouaiw" style={link}>
                Book a short call
              </Link>
            </Text>
            <Text style={text}>
              Talk soon,
            </Text>
            <Text style={signature}>Ludvig</Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
};

// 7. Super Search (6 Days After Signup)
export const SuperSearchEmail = ({ name }: EmailProps) => {
  return (
    <Html>
      <Head />
      <Preview>Search across email, calendar, and tasks</Preview>
      <Body style={main}>
        <Container style={container}>
          <Section style={section}>
            <Heading style={h1}>Search across email, calendar, and tasks</Heading>
            <Text style={text}>Hey {name ? name : 'there'},</Text>
            <Text style={text}>
              Todus's Super Search lets you use plain language to find threads, meetings, and tasks without thinking about exact words.
            </Text>
            <Text style={text}>Try asking for:</Text>
            <Text style={listItem}>emails from John</Text>
            <Text style={listItem}>threads from last week</Text>
            <Text style={listItem}>unread reminders with attachments</Text>
            <Text style={listItem}>calendar invites about product planning</Text>
            <Text style={listItem}>tasks due this afternoon</Text>
            <Text style={text}>
              No syntax, no filters. Just type as you would tell a teammate and the AI handles the rest.
            </Text>
            <Text style={text}>
              Let’s chat about how Super Search fits into your workflow.{' '}
              <Link href="https://cal.com/ludvig-hedin-iouaiw" style={link}>
                Book a short call
              </Link>
            </Text>
            <Text style={text}>
              See you soon,
            </Text>
            <Text style={signature}>Ludvig</Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
};

// Todus Pro Welcome Email
export const TodusProWelcomeEmail = ({ name }: EmailProps) => {
  return (
    <Html>
      <Head />
      <Preview>Welcome to Todus Pro</Preview>
      <Body style={main}>
        <Container style={container}>
          <Section style={section}>
            <Heading style={h1}>You're on Todus Pro</Heading>
            <Text style={text}>Hey {name ? name : 'there'},</Text>
            <Text style={text}>
              You just unlocked Todus Pro — unlimited email, calendar, tasks, automations, and the AI assistant.
            </Text>
            <Text style={text}>You now have access to:</Text>
            <Text style={listItem}>Unlimited email and calendar accounts</Text>
            <Text style={listItem}>Full AI-powered chat with your workspace</Text>
            <Text style={listItem}>Instant task and meeting summaries</Text>
            <Text style={listItem}>One-click AI writing and smart replies</Text>
            <Text style={listItem}>Auto labeling and custom shortcuts</Text>
            <Text style={listItem}>Priority support and early build access</Text>
            <Text style={text}>
              You're part of a group who want a calm, modern workspace. Welcome.
            </Text>
            <Text style={text}>
              Need help getting the most out of Pro?{' '}
              <Link href="https://cal.com/ludvig-hedin-iouaiw" style={link}>
                Book a short call
              </Link>
            </Text>
            <Text style={text}>
              Let's make this the smartest place you manage work.
            </Text>
            <Text style={signature}>Ludvig</Text>
            <Text style={text}>
              P.S. If anything feels confusing, reply to this email. We are here to help.
            </Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
};

// Todus Cancellation Email
export const TodusCancellationEmail = ({ name }: EmailProps) => {
  return (
    <Html>
      <Head />
      <Preview>You've canceled Todus Pro</Preview>
      <Body style={main}>
        <Container style={container}>
          <Section style={section}>
            <Heading style={h1}>You've canceled Todus Pro</Heading>
            <Text style={text}>Hey {name ? name : 'there'},</Text>
            <Text style={text}>
              I saw you canceled your Todus Pro subscription. Totally okay — tools evolve, as do priorities.
            </Text>
            <Text style={text}>
              I'd love to hear what we could improve.{' '}
              <Link href="https://cal.com/ludvig-hedin-iouaiw" style={link}>
                Book a short call
              </Link>
            </Text>
            <Text style={text}>You'll still have access to the free plan:</Text>
            <Text style={listItem}>1 email connection</Text>
            <Text style={listItem}>Basic labeling</Text>
            <Text style={listItem}>Limited AI chat and writing assistance</Text>
            <Text style={text}>
              No hard feelings. We are rooting for you, even if your workflow continues elsewhere.
            </Text>
            <Text style={text}>
              Thanks for giving Todus a shot,
            </Text>
            <Text style={signature}>Ludvig</Text>
            <Text style={text}>
              P.S. If you ever want to come back, your workspace will be waiting.
            </Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
}; 
