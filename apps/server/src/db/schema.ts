import {
  pgTableCreator,
  text,
  timestamp,
  boolean,
  integer,
  jsonb,
  primaryKey,
  unique,
  index,
} from 'drizzle-orm/pg-core';
import type { AnyPgColumn } from 'drizzle-orm/pg-core';
import { defaultUserSettings } from '../lib/schemas';

export const createTable = pgTableCreator((name) => `mail0_${name}`);

export const user = createTable('user', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
  email: text('email').notNull().unique(),
  emailVerified: boolean('email_verified').notNull(),
  image: text('image'),
  createdAt: timestamp('created_at').notNull(),
  updatedAt: timestamp('updated_at').notNull(),
  defaultConnectionId: text('default_connection_id'),
  customPrompt: text('custom_prompt'),
  phoneNumber: text('phone_number').unique(),
  phoneNumberVerified: boolean('phone_number_verified'),
});

export const session = createTable(
  'session',
  {
    id: text('id').primaryKey(),
    expiresAt: timestamp('expires_at').notNull(),
    token: text('token').notNull().unique(),
    createdAt: timestamp('created_at').notNull(),
    updatedAt: timestamp('updated_at').notNull(),
    ipAddress: text('ip_address'),
    userAgent: text('user_agent'),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
  },
  (t) => [
    index('session_user_id_idx').on(t.userId),
    index('session_expires_at_idx').on(t.expiresAt),
  ],
);

export const sessionMetadata = createTable(
  'session_metadata',
  {
    sessionId: text('session_id')
      .primaryKey()
      .references(() => session.id, { onDelete: 'cascade' }),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    deviceLabel: text('device_label'),
    deviceType: text('device_type'),
    osName: text('os_name'),
    browserName: text('browser_name'),
    city: text('city'),
    region: text('region'),
    country: text('country'),
    lastSeenAt: timestamp('last_seen_at').notNull().defaultNow(),
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at')
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [
    index('session_metadata_user_id_idx').on(t.userId),
    index('session_metadata_updated_at_idx').on(t.updatedAt),
  ],
);

export const account = createTable(
  'account',
  {
    id: text('id').primaryKey(),
    accountId: text('account_id').notNull(),
    providerId: text('provider_id').notNull(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    accessToken: text('access_token'),
    refreshToken: text('refresh_token'),
    idToken: text('id_token'),
    accessTokenExpiresAt: timestamp('access_token_expires_at'),
    refreshTokenExpiresAt: timestamp('refresh_token_expires_at'),
    scope: text('scope'),
    password: text('password'),
    createdAt: timestamp('created_at').notNull(),
    updatedAt: timestamp('updated_at').notNull(),
  },
  (t) => [
    index('account_user_id_idx').on(t.userId),
    index('account_provider_user_id_idx').on(t.providerId, t.userId),
    index('account_expires_at_idx').on(t.accessTokenExpiresAt),
  ],
);

export const userHotkeys = createTable(
  'user_hotkeys',
  {
    userId: text('user_id')
      .primaryKey()
      .references(() => user.id, { onDelete: 'cascade' }),
    shortcuts: jsonb('shortcuts').notNull(),
    createdAt: timestamp('created_at').notNull(),
    updatedAt: timestamp('updated_at').notNull(),
  },
  (t) => [index('user_hotkeys_shortcuts_idx').on(t.shortcuts)],
);

export const verification = createTable(
  'verification',
  {
    id: text('id').primaryKey(),
    identifier: text('identifier').notNull(),
    value: text('value').notNull(),
    expiresAt: timestamp('expires_at').notNull(),
    createdAt: timestamp('created_at'),
    updatedAt: timestamp('updated_at'),
  },
  (t) => [
    index('verification_identifier_idx').on(t.identifier),
    index('verification_expires_at_idx').on(t.expiresAt),
  ],
);

export const earlyAccess = createTable(
  'early_access',
  {
    id: text('id').primaryKey(),
    email: text('email').notNull().unique(),
    createdAt: timestamp('created_at').notNull(),
    updatedAt: timestamp('updated_at').notNull(),
    isEarlyAccess: boolean('is_early_access').notNull().default(false),
    hasUsedTicket: text('has_used_ticket').default(''),
  },
  (t) => [index('early_access_is_early_access_idx').on(t.isEarlyAccess)],
);

export const connection = createTable(
  'connection',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    email: text('email').notNull(),
    name: text('name'),
    picture: text('picture'),
    accessToken: text('access_token'),
    refreshToken: text('refresh_token'),
    scope: text('scope').notNull(),
    providerId: text('provider_id').$type<'google' | 'microsoft'>().notNull(),
    expiresAt: timestamp('expires_at').notNull(),
    createdAt: timestamp('created_at').notNull(),
    updatedAt: timestamp('updated_at').notNull(),
  },
  (t) => [
    unique().on(t.userId, t.email),
    index('connection_user_id_idx').on(t.userId),
    index('connection_expires_at_idx').on(t.expiresAt),
    index('connection_provider_id_idx').on(t.providerId),
  ],
);

export const summary = createTable(
  'summary',
  {
    messageId: text('message_id').primaryKey(),
    content: text('content').notNull(),
    createdAt: timestamp('created_at').notNull(),
    updatedAt: timestamp('updated_at').notNull(),
    connectionId: text('connection_id')
      .notNull()
      .references(() => connection.id, { onDelete: 'cascade' }),
    saved: boolean('saved').notNull().default(false),
    tags: text('tags'),
    suggestedReply: text('suggested_reply'),
  },
  (t) => [
    index('summary_connection_id_idx').on(t.connectionId),
    index('summary_connection_id_saved_idx').on(t.connectionId, t.saved),
    index('summary_saved_idx').on(t.saved),
  ],
);

// Testing
export const note = createTable(
  'note',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    threadId: text('thread_id').notNull(),
    content: text('content').notNull(),
    color: text('color').notNull().default('default'),
    isPinned: boolean('is_pinned').default(false),
    order: integer('order').notNull().default(0),
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at').notNull().defaultNow(),
  },
  (t) => [
    index('note_user_id_idx').on(t.userId),
    index('note_thread_id_idx').on(t.threadId),
    index('note_user_thread_idx').on(t.userId, t.threadId),
    index('note_is_pinned_idx').on(t.isPinned),
  ],
);

export const userSettings = createTable(
  'user_settings',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' })
      .unique(),
    settings: jsonb('settings')
      .$type<typeof defaultUserSettings>()
      .notNull()
      .default(defaultUserSettings),
    createdAt: timestamp('created_at').notNull(),
    updatedAt: timestamp('updated_at').notNull(),
  },
  (t) => [index('user_settings_settings_idx').on(t.settings)],
);

export const writingStyleMatrix = createTable(
  'writing_style_matrix',
  {
    connection_id: text('connection_id')
      .notNull()
      .references(() => connection.id, { onDelete: 'cascade' }),
    num_messages: integer('num_messages').notNull(),
    // TODO: way too much pain to get this type to work,
    // revisit later
    style: jsonb('style').$type<unknown>().notNull(),
    updated_at: timestamp('updated_at')
      .defaultNow()
      .notNull()
      .$onUpdate(() => new Date()),
  },
  (table) => {
    return [
      primaryKey({
        columns: [table.connection_id],
      }),
      index('writing_style_matrix_style_idx').on(table.style),
    ];
  },
);

export const jwks = createTable(
  'jwks',
  {
    id: text('id').primaryKey(),
    publicKey: text('public_key').notNull(),
    privateKey: text('private_key').notNull(),
    createdAt: timestamp('created_at').notNull(),
  },
  (t) => [index('jwks_created_at_idx').on(t.createdAt)],
);

export const oauthApplication = createTable(
  'oauth_application',
  {
    id: text('id').primaryKey(),
    name: text('name'),
    icon: text('icon'),
    metadata: text('metadata'),
    clientId: text('client_id').unique(),
    clientSecret: text('client_secret'),
    redirectURLs: text('redirect_u_r_ls'),
    type: text('type'),
    disabled: boolean('disabled'),
    userId: text('user_id').references(() => user.id, { onDelete: 'cascade' }),
    createdAt: timestamp('created_at'),
    updatedAt: timestamp('updated_at'),
  },
  (t) => [
    index('oauth_application_user_id_idx').on(t.userId),
    index('oauth_application_disabled_idx').on(t.disabled),
  ],
);

export const oauthAccessToken = createTable(
  'oauth_access_token',
  {
    id: text('id').primaryKey(),
    accessToken: text('access_token').unique(),
    refreshToken: text('refresh_token').unique(),
    accessTokenExpiresAt: timestamp('access_token_expires_at'),
    refreshTokenExpiresAt: timestamp('refresh_token_expires_at'),
    clientId: text('client_id').references(() => oauthApplication.clientId, { onDelete: 'cascade' }),
    userId: text('user_id').references(() => user.id, { onDelete: 'cascade' }),
    scopes: text('scopes'),
    createdAt: timestamp('created_at'),
    updatedAt: timestamp('updated_at'),
  },
  (t) => [
    index('oauth_access_token_user_id_idx').on(t.userId),
    index('oauth_access_token_client_id_idx').on(t.clientId),
    index('oauth_access_token_expires_at_idx').on(t.accessTokenExpiresAt),
  ],
);

export const oauthConsent = createTable(
  'oauth_consent',
  {
    id: text('id').primaryKey(),
    clientId: text('client_id').references(() => oauthApplication.clientId, { onDelete: 'cascade' }),
    userId: text('user_id').references(() => user.id, { onDelete: 'cascade' }),
    scopes: text('scopes'),
    createdAt: timestamp('created_at'),
    updatedAt: timestamp('updated_at'),
    consentGiven: boolean('consent_given'),
  },
  (t) => [
    index('oauth_consent_user_id_idx').on(t.userId),
    index('oauth_consent_client_id_idx').on(t.clientId),
    index('oauth_consent_given_idx').on(t.consentGiven),
  ],
);

// ─── Meeting & Recording Tables ──────────────────────────────────────────
// Recall.ai-powered meeting recordings, transcripts, and AI recaps.

export const meetIntegration = createTable(
  'meet_integration',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' })
      .unique(),
    botName: text('bot_name').notNull().default('Note Taker'),
    isEnabled: boolean('is_enabled').notNull().default(true),
    autoJoin: boolean('auto_join').notNull().default(false),
    joinEarlyMinutes: integer('join_early_minutes').notNull().default(1),
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at')
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  () => [],
);

export const meeting = createTable(
  'meeting',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    integrationId: text('integration_id').references(() => meetIntegration.id, {
      onDelete: 'set null',
    }),
    googleEventId: text('google_event_id'),
    calendarId: text('calendar_id'),
    title: text('title').notNull(),
    description: text('description'),
    meetUrl: text('meet_url').notNull(),
    startsAt: timestamp('starts_at').notNull(),
    endsAt: timestamp('ends_at'),
    recallBotId: text('recall_bot_id'),
    recallMeetingId: text('recall_meeting_id'),
    botJoinedAt: timestamp('bot_joined_at'),
    botLeftAt: timestamp('bot_left_at'),
    status: text('status')
      .$type<'scheduled' | 'bot_joining' | 'recording' | 'processing' | 'ready' | 'failed' | 'cancelled'>()
      .notNull()
      .default('scheduled'),
    errorMessage: text('error_message'),
    participants: jsonb('participants'),
    aiSummary: text('ai_summary'),
    actionItems: jsonb('action_items'),
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at')
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [
    index('meeting_user_id_idx').on(t.userId),
    index('meeting_integration_id_idx').on(t.integrationId),
    index('meeting_status_idx').on(t.status),
    index('meeting_recall_bot_id_idx').on(t.recallBotId),
    index('meeting_starts_at_idx').on(t.startsAt),
    index('meeting_user_status_idx').on(t.userId, t.status),
    index('meeting_google_event_idx').on(t.userId, t.googleEventId),
  ],
);

export const meetingMedia = createTable(
  'meeting_media',
  {
    id: text('id').primaryKey(),
    meetingId: text('meeting_id')
      .notNull()
      .references(() => meeting.id, { onDelete: 'cascade' }),
    mediaType: text('media_type')
      .$type<'audio_mixed' | 'video_mixed' | 'transcript'>()
      .notNull(),
    recallMediaId: text('recall_media_id').unique(),
    url: text('url').notNull(),
    fileName: text('file_name'),
    fileSize: integer('file_size'),
    duration: integer('duration'),
    isReady: boolean('is_ready').notNull().default(false),
    readyAt: timestamp('ready_at'),
    metadata: jsonb('metadata'),
    createdAt: timestamp('created_at').notNull().defaultNow(),
  },
  (t) => [
    index('meeting_media_meeting_id_idx').on(t.meetingId),
    index('meeting_media_type_idx').on(t.mediaType),
  ],
);

export const meetingTranscript = createTable(
  'meeting_transcript',
  {
    id: text('id').primaryKey(),
    meetingId: text('meeting_id')
      .notNull()
      .references(() => meeting.id, { onDelete: 'cascade' }),
    startTime: integer('start_time').notNull(),
    endTime: integer('end_time'),
    speakerName: text('speaker_name').notNull(),
    speakerId: text('speaker_id'),
    text: text('text').notNull(),
    confidence: text('confidence'),
    isFromRealtime: boolean('is_from_realtime').notNull().default(false),
    recallSegmentId: text('recall_segment_id').unique(),
    createdAt: timestamp('created_at').notNull().defaultNow(),
  },
  (t) => [
    index('meeting_transcript_meeting_id_idx').on(t.meetingId),
    index('meeting_transcript_meeting_time_idx').on(t.meetingId, t.startTime),
  ],
);

// ─── Task Management Tables ────────────────────────────────────────────
// Used by the unified iOS/macOS app for task + folder sync.

export const taskFolder = createTable(
  'task_folder',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    createdAt: timestamp('created_at').notNull().defaultNow(),
  },
  (t) => [
    index('task_folder_user_id_idx').on(t.userId),
  ],
);

export const task = createTable(
  'task',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    title: text('title').notNull(),
    description: text('description').default(''),
    status: text('status').$type<'todo' | 'doing' | 'done'>().notNull().default('todo'),
    priority: text('priority').$type<'none' | 'low' | 'medium' | 'high'>().notNull().default('none'),
    dueDate: timestamp('due_date'),
    folderId: text('folder_id').references(() => taskFolder.id, { onDelete: 'set null' }),
    reminderIdentifier: text('reminder_identifier'),
    // Cross-entity links — nullable, no FK (email threads and calendar events are external)
    emailThreadId: text('email_thread_id'),
    eventId: text('event_id'),
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at').notNull().defaultNow(),
  },
  (t) => [
    index('task_user_id_idx').on(t.userId),
    index('task_folder_id_idx').on(t.folderId),
    index('task_status_idx').on(t.status),
    index('task_due_date_idx').on(t.dueDate),
    index('task_user_status_idx').on(t.userId, t.status),
    index('task_email_thread_id_idx').on(t.emailThreadId),
    index('task_event_id_idx').on(t.eventId),
  ],
);

export const emailTemplate = createTable(
  'email_template',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    subject: text('subject'),
    body: text('body'),
    to: jsonb('to'),
    cc: jsonb('cc'),
    bcc: jsonb('bcc'),
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at').notNull().defaultNow(),
  },
  (t) => [
    index('idx_mail0_email_template_user_id').on(t.userId),
    unique('mail0_email_template_user_id_name_unique').on(t.userId, t.name),
  ],
);

export const aiConversation = createTable(
  'ai_conversation',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    folderId: text('folder_id').references(() => taskFolder.id, { onDelete: 'set null' }),
    title: text('title').notNull().default(''),
    // Full conversation stored as JSON array of {role, content, mentions?}
    messages: jsonb('messages').notNull().default('[]'),
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at').notNull().defaultNow(),
  },
  (t) => [
    index('ai_conversation_user_id_idx').on(t.userId),
    index('ai_conversation_folder_id_idx').on(t.folderId),
    index('ai_conversation_updated_at_idx').on(t.updatedAt),
  ],
);

// ─── Shared Conversations ─────────────────────────────────────────────────────
// A frozen, public (or password-protected) snapshot of an aiConversation.
// Access control is enforced at the tRPC layer — the table itself has no RLS.
export const sharedConversation = createTable(
  'shared_conversation',
  {
    id: text('id').primaryKey(),
    ownerUserId: text('owner_user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    conversationId: text('conversation_id')
      .notNull()
      .references(() => aiConversation.id, { onDelete: 'cascade' }),
    // Short URL-safe slug used in /share/[slug]
    slug: text('slug').notNull().unique(),
    title: text('title').notNull().default(''),
    // PBKDF2-derived hash via Web Crypto API (100k iterations, SHA-256). null = no password.
    passwordHash: text('password_hash'),
    // Base64-encoded 16-byte random salt, stored alongside hash
    passwordSalt: text('password_salt'),
    expiresAt: timestamp('expires_at'),    // null = never expires
    revokedAt: timestamp('revoked_at'),    // null = active; set to disable the link
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at')
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [
    index('shared_conversation_owner_idx').on(t.ownerUserId),
    index('shared_conversation_slug_idx').on(t.slug),
    index('shared_conversation_conversation_id_idx').on(t.conversationId),
  ],
);

// ─── Group Chats ──────────────────────────────────────────────────────────────
// Multi-user rooms where multiple humans share a conversation with the AI.

export const group = createTable(
  'group',
  {
    id: text('id').primaryKey(),
    ownerUserId: text('owner_user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    slug: text('slug').notNull().unique(),                // display URL: /g/[slug]
    inviteToken: text('invite_token').notNull().unique(), // opaque join token
    // 'mention' = AI responds only when @ai appears; 'always' = responds to every message
    aiMode: text('ai_mode').$type<'mention' | 'always'>().notNull().default('mention'),
    maxMembers: integer('max_members').notNull().default(20),
    deletedAt: timestamp('deleted_at'),                   // soft-delete
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at')
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [
    index('group_owner_idx').on(t.ownerUserId),
    index('group_slug_idx').on(t.slug),
    index('group_invite_token_idx').on(t.inviteToken),
    index('group_deleted_at_idx').on(t.deletedAt),
  ],
);

export const groupMember = createTable(
  'group_member',
  {
    groupId: text('group_id')
      .notNull()
      .references(() => group.id, { onDelete: 'cascade' }),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    role: text('role').$type<'owner' | 'member'>().notNull().default('member'),
    joinedAt: timestamp('joined_at').notNull().defaultNow(),
  },
  (t) => [
    primaryKey({ columns: [t.groupId, t.userId] }),
    index('group_member_user_id_idx').on(t.userId),
  ],
);

export const groupMessage = createTable(
  'group_message',
  {
    id: text('id').primaryKey(),
    groupId: text('group_id')
      .notNull()
      .references(() => group.id, { onDelete: 'cascade' }),
    senderUserId: text('sender_user_id')
      .references(() => user.id, { onDelete: 'set null' }), // null for AI / system messages
    senderType: text('sender_type').$type<'user' | 'ai' | 'system'>().notNull(),
    content: text('content').notNull(),
    createdAt: timestamp('created_at').notNull().defaultNow(),
  },
  (t) => [
    index('group_message_group_id_idx').on(t.groupId),
    index('group_message_sender_user_id_idx').on(t.senderUserId),
    // Composite index supports paginated queries ordered by (groupId, createdAt)
    index('group_message_group_created_idx').on(t.groupId, t.createdAt),
  ],
);

// ─── Docs ─────────────────────────────────────────────────────────────────────
// Notion-style document workspaces and pages. Each workspace belongs to a user
// and holds a tree of docs (nested via self-referential parentId). Content is
// stored as Tiptap JSONContent (jsonb) alongside a plaintext mirror for search.

export const docWorkspace = createTable(
  'doc_workspace',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    // Optional workspace icon displayed in the sidebar
    emoji: text('emoji'),
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at')
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [index('doc_workspace_user_id_idx').on(t.userId)],
);

export const doc = createTable(
  'doc',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    // Optional: null means the doc lives at the top level outside any workspace
    workspaceId: text('workspace_id').references(() => docWorkspace.id, { onDelete: 'cascade' }),
    // Self-referential FK for nested pages (null = root-level doc within its workspace).
    // Explicit return type annotation is required to satisfy TypeScript's circular reference check.
    // eslint-disable-next-line @typescript-eslint/no-use-before-define
    parentId: text('parent_id').references((): AnyPgColumn => doc.id, { onDelete: 'cascade' }),
    title: text('title').notNull().default('Untitled'),
    // Tiptap JSONContent stored as jsonb; null until the user writes something
    content: jsonb('content'),
    // Plaintext mirror of content for full-text search without parsing jsonb
    contentText: text('content_text'),
    emoji: text('emoji'),
    order: integer('order').notNull().default(0),
    // Cross-entity links — nullable, no FK (threads/events/tasks are external)
    linkedThreadId: text('linked_thread_id'),
    linkedEventId: text('linked_event_id'),
    linkedTaskId: text('linked_task_id'),
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at')
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [
    index('doc_user_id_idx').on(t.userId),
    index('doc_workspace_id_idx').on(t.workspaceId),
    index('doc_parent_id_idx').on(t.parentId),
  ],
);
