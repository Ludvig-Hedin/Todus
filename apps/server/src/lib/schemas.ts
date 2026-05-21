import { z } from 'zod';

export const assistantAutoSendScenarioSchema = z.enum([
  'acknowledgment',
  'simple_confirmation',
  'scheduling_confirmation',
]);

export const assistantQuietHoursSchema = z.object({
  startHour: z.number().int().min(0).max(23).default(22),
  endHour: z.number().int().min(0).max(23).default(7),
});

export const assistantAutomationPolicySchema = z.object({
  autoSummarizeLongThreads: z.boolean().default(true),
  suggestTasksFromEmail: z.boolean().default(true),
  suggestEventsFromEmail: z.boolean().default(true),
  autoDraftReplies: z.boolean().default(true),
  smartReplyNudges: z.boolean().default(true),
  smartDeadlineNudges: z.boolean().default(true),
  assistantThreadActionsVisible: z.boolean().default(true),
  briefingEnabled: z.boolean().default(true),
  showHomeBriefing: z.boolean().default(true),
  trackWaitingOnThreads: z.boolean().default(true),
  peopleMemoryEnabled: z.boolean().default(true),
  batchApprovalEnabled: z.boolean().default(false),
  workdayStartHour: z.number().int().min(0).max(23).default(8),
  workdayEndHour: z.number().int().min(0).max(23).default(18),
  excludedSenderPatterns: z.array(z.string()).default([]),
  autoSendExperimentEnabled: z.boolean().default(false),
  autoSendAllowedScenarios: z.array(assistantAutoSendScenarioSchema).default(['acknowledgment']),
  autoSendQuietHours: assistantQuietHoursSchema.default({
    startHour: 22,
    endHour: 7,
  }),
});

export type AssistantAutomationPolicy = z.infer<typeof assistantAutomationPolicySchema>;

export const defaultAssistantAutomationPolicy: AssistantAutomationPolicy = {
  autoSummarizeLongThreads: true,
  suggestTasksFromEmail: true,
  suggestEventsFromEmail: true,
  autoDraftReplies: true,
  smartReplyNudges: true,
  smartDeadlineNudges: true,
  assistantThreadActionsVisible: true,
  briefingEnabled: true,
  showHomeBriefing: true,
  trackWaitingOnThreads: true,
  peopleMemoryEnabled: true,
  batchApprovalEnabled: false,
  workdayStartHour: 8,
  workdayEndHour: 18,
  excludedSenderPatterns: [],
  autoSendExperimentEnabled: false,
  autoSendAllowedScenarios: ['acknowledgment'],
  autoSendQuietHours: {
    startHour: 22,
    endHour: 7,
  },
};

export const assistantDefaultExcludedSendersPlaceholder = [
  'notifications@',
  'no-reply@',
  'calendar-notification@',
].join('\n');

/**
 * Per-user calendar visibility prefs synced across iOS/macOS/web.
 *
 * `hiddenCalendarIds` uses composite IDs:
 *   - Apple: `apple:{EKCalendar.calendarIdentifier}`
 *   - Google: `google:{connectionId}:{googleCalendarId}`
 *
 * Account keys for `defaultCalendarByAccount` are `apple` or `google:{connectionId}`.
 */
export const calendarPreferencesSchema = z.object({
  hiddenCalendarIds: z.array(z.string()).default([]),
  defaultCalendarId: z.string().optional(),
  defaultCalendarByAccount: z.record(z.string(), z.string()).default({}),
  /** When true, hide Apple-side mirrors of calendars also covered by a Google connection. */
  preferGoogleOverAppleDuplicates: z.boolean().default(true),
});

export type CalendarPreferences = z.infer<typeof calendarPreferencesSchema>;

export const defaultCalendarPreferences: CalendarPreferences = {
  hiddenCalendarIds: [],
  defaultCalendarByAccount: {},
  preferGoogleOverAppleDuplicates: true,
};

export const serializedFileSchema = z.object({
  name: z.string(),
  type: z.string(),
  size: z.number(),
  lastModified: z.number(),
  base64: z.string(),
});

export const deserializeFiles = async (serializedFiles: z.infer<typeof serializedFileSchema>[]) => {
  return await Promise.all(
    serializedFiles.map((data) => {
      const file = Buffer.from(data.base64, 'base64');
      const blob = new Blob([file], { type: data.type });
      const newFile = new File([blob], data.name, {
        type: data.type,
        lastModified: data.lastModified,
      });
      return newFile;
    }),
  );
};

export const createDraftData = z.object({
  to: z.string(),
  cc: z.string().optional(),
  bcc: z.string().optional(),
  subject: z.string(),
  message: z.string(),
  attachments: z.array(serializedFileSchema).optional(),
  id: z.string().nullable(),
  threadId: z.string().nullable(),
  fromEmail: z.string().nullable(),
});

export type CreateDraftData = z.infer<typeof createDraftData>;

export const mailCategorySchema = z.object({
  id: z
    .string()
    .regex(
      /^[a-zA-Z0-9\-_ ]+$/,
      'Category ID must contain only alphanumeric characters, hyphens, underscores, and spaces',
    ),
  name: z.string(),
  searchValue: z.string(),
  order: z.number().int(),
  icon: z.string().optional(),
  isDefault: z.boolean().optional().default(false),
});

export type MailCategory = z.infer<typeof mailCategorySchema>;

export const defaultMailCategories: MailCategory[] = [
  {
    id: 'Important',
    name: 'Important',
    searchValue: 'IMPORTANT',
    order: 0,
    icon: 'Lightning',
    isDefault: false,
  },
  {
    id: 'All Mail',
    name: 'All Mail',
    searchValue: '',
    order: 1,
    icon: 'Mail',
    isDefault: true,
  },
  {
    id: 'Unread',
    name: 'Unread',
    searchValue: 'UNREAD',
    order: 5,
    icon: 'ScanEye',
    isDefault: false,
  },
];

const categoriesSchema = z.array(mailCategorySchema).superRefine((cats, ctx) => {
  const orders = cats.map((c) => c.order);
  if (new Set(orders).size !== orders.length) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'Each mail category must have a unique order number',
    });
  }

  const defaultCount = cats.filter((c) => c.isDefault).length;
  if (defaultCount !== 1) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'Exactly one mail category must be set as default',
    });
  }
});

export const userSettingsSchema = z.object({
  language: z.string(),
  timezone: z.string(),
  location: z.string().default(''),
  dynamicContent: z.boolean().optional(),
  externalImages: z.boolean(),
  contextAboutYou: z.string().default(''),
  customPrompt: z.string().default(''),
  isOnboarded: z.boolean().optional(),
  welcomeEmailSent: z.boolean().default(false),
  trustedSenders: z.string().array().optional(),
  colorTheme: z.enum(['light', 'dark', 'system']).default('system'),
  todusSignature: z.boolean().default(true),
  categories: categoriesSchema.optional(),
  defaultEmailAlias: z.string().optional(),
  undoSendEnabled: z.boolean().default(false),
  imageCompression: z.enum(['low', 'medium', 'original']).default('medium'),
  autoRead: z.boolean().default(true),
  animations: z.boolean().default(false),
  assistantAutomationPolicy: assistantAutomationPolicySchema.default(defaultAssistantAutomationPolicy),
  calendarPreferences: calendarPreferencesSchema.default(defaultCalendarPreferences),
  // AI provider & model selection — allows users to choose their preferred LLM provider
  // and optionally use a local Ollama instance for privacy / cost / offline use.
  aiProvider: z
    .enum(['auto', 'openai', 'anthropic', 'google', 'groq', 'openrouter', 'ollama'])
    .default('auto'),
  aiModel: z.string().default(''),
  ollamaBaseUrl: z.string().default('http://localhost:11434'),

  // Cross-device sync additions — keys match iOS @AppStorage + macOS @AppStorage so all
  // three platforms read/write the same record via trpc.settings.save / settings.get.
  // AI capability permissions
  aiCanReadTasks: z.boolean().default(true),
  aiCanWriteTasks: z.boolean().default(true),
  aiCanReadCalendar: z.boolean().default(true),
  aiCanWriteCalendar: z.boolean().default(true),
  aiCanReadEmail: z.boolean().default(true),
  aiCanSendEmail: z.boolean().default(true),

  // Appearance — shared accent + default task view
  accentColor: z.enum(['blue', 'indigo', 'teal', 'green', 'orange', 'rose']).default('blue'),
  defaultTaskView: z.enum(['list', 'board', 'table', 'calendar', 'dates']).default('list'),

  // App preferences (web + macOS surface these; iOS reuses where applicable)
  openOnLaunch: z.enum(['home', 'inbox', 'tasks', 'calendar']).default('home'),
  resumeLastViewedPage: z.boolean().default(true),
  compactSidebar: z.boolean().default(false),
  showUnreadBadge: z.boolean().default(true),
  focusModeEnabled: z.boolean().default(false),
  groupByThread: z.boolean().default(true),
  hideAppleSideGmailDuplicates: z.boolean().default(true),
});

export type UserSettings = z.infer<typeof userSettingsSchema>;

export const defaultUserSettings: UserSettings = {
  language: 'en',
  timezone: 'UTC',
  location: '',
  dynamicContent: false,
  externalImages: true,
  contextAboutYou: '',
  customPrompt: '',
  trustedSenders: [],
  isOnboarded: false,
  welcomeEmailSent: false,
  colorTheme: 'system',
  todusSignature: true,
  autoRead: true,
  defaultEmailAlias: '',
  categories: defaultMailCategories,
  undoSendEnabled: false,
  imageCompression: 'medium',
  animations: false,
  assistantAutomationPolicy: defaultAssistantAutomationPolicy,
  calendarPreferences: defaultCalendarPreferences,
  aiProvider: 'auto',
  aiModel: '',
  ollamaBaseUrl: 'http://localhost:11434',
  aiCanReadTasks: true,
  aiCanWriteTasks: true,
  aiCanReadCalendar: true,
  aiCanWriteCalendar: true,
  aiCanReadEmail: true,
  aiCanSendEmail: true,
  accentColor: 'blue',
  defaultTaskView: 'list',
  openOnLaunch: 'home',
  resumeLastViewedPage: true,
  compactSidebar: false,
  showUnreadBadge: true,
  focusModeEnabled: false,
  groupByThread: true,
  hideAppleSideGmailDuplicates: true,
};

type DeepPartial<T> = T extends Array<infer U>
  ? Array<DeepPartial<U>>
  : T extends object
    ? { [P in keyof T]?: DeepPartial<T[P]> }
    : T;

type UserSettingsMergeInput = Omit<DeepPartial<UserSettings>, 'categories'> & {
  categories?: MailCategory[];
};

export const mergeUserSettings = (
  current: UserSettingsMergeInput | undefined,
  incoming: UserSettingsMergeInput,
): UserSettings => {
  return userSettingsSchema.parse({
    ...defaultUserSettings,
    ...current,
    ...incoming,
    assistantAutomationPolicy: {
      ...defaultAssistantAutomationPolicy,
      ...(current?.assistantAutomationPolicy ?? {}),
      ...(incoming.assistantAutomationPolicy ?? {}),
      autoSendQuietHours: {
        ...defaultAssistantAutomationPolicy.autoSendQuietHours,
        ...(current?.assistantAutomationPolicy?.autoSendQuietHours ?? {}),
        ...(incoming.assistantAutomationPolicy?.autoSendQuietHours ?? {}),
      },
    },
    calendarPreferences: {
      ...defaultCalendarPreferences,
      ...(current?.calendarPreferences ?? {}),
      ...(incoming.calendarPreferences ?? {}),
      defaultCalendarByAccount: {
        ...(current?.calendarPreferences?.defaultCalendarByAccount ?? {}),
        ...(incoming.calendarPreferences?.defaultCalendarByAccount ?? {}),
      },
    },
  });
};
