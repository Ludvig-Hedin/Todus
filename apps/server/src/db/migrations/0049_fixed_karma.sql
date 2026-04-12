CREATE TABLE "mail0_assistant_briefing_snapshot" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"snapshot_key" text NOT NULL,
	"payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "mail0_assistant_briefing_snapshot_user_id_snapshot_key_unique" UNIQUE("user_id","snapshot_key")
);
--> statement-breakpoint
CREATE TABLE "mail0_assistant_feedback" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"target_type" text NOT NULL,
	"target_id" text NOT NULL,
	"feedback" text NOT NULL,
	"note" text,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "mail0_assistant_open_loop" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"unique_key" text NOT NULL,
	"type" text NOT NULL,
	"queue" text NOT NULL,
	"status" text DEFAULT 'open' NOT NULL,
	"title" text NOT NULL,
	"summary" text NOT NULL,
	"confidence_pct" integer DEFAULT 50 NOT NULL,
	"reason" text DEFAULT '' NOT NULL,
	"suggested_action_label" text,
	"source_thread_id" text,
	"source_meeting_id" text,
	"source_task_id" text,
	"source_event_id" text,
	"person_email" text,
	"workstream_key" text,
	"evidence" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"snoozed_until" timestamp,
	"last_reviewed_at" timestamp,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "mail0_assistant_open_loop_user_id_unique_key_unique" UNIQUE("user_id","unique_key")
);
--> statement-breakpoint
CREATE TABLE "mail0_assistant_person_memory" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"email" text NOT NULL,
	"display_name" text,
	"company" text,
	"relationship_summary" text DEFAULT '' NOT NULL,
	"unresolved_asks" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"promises" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"preferred_follow_up_cadence_days" integer,
	"recent_thread_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"recent_meeting_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"recent_task_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"last_interaction_at" timestamp,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "mail0_assistant_person_memory_user_id_email_unique" UNIQUE("user_id","email")
);
--> statement-breakpoint
CREATE TABLE "mail0_assistant_prepared_action" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"unique_key" text NOT NULL,
	"type" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"title" text NOT NULL,
	"summary" text NOT NULL,
	"confidence_pct" integer DEFAULT 50 NOT NULL,
	"reason" text DEFAULT '' NOT NULL,
	"preview" text,
	"payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"source_thread_id" text,
	"source_meeting_id" text,
	"person_email" text,
	"workstream_key" text,
	"evidence" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "mail0_assistant_prepared_action_user_id_unique_key_unique" UNIQUE("user_id","unique_key")
);
--> statement-breakpoint
CREATE TABLE "mail0_assistant_workstream_memory" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"key" text NOT NULL,
	"title" text NOT NULL,
	"summary" text DEFAULT '' NOT NULL,
	"status" text DEFAULT 'active' NOT NULL,
	"pending_decisions" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"risks" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"related_people" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"related_thread_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"related_meeting_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"related_task_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"next_milestone" text,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "mail0_assistant_workstream_memory_user_id_key_unique" UNIQUE("user_id","key")
);
--> statement-breakpoint
CREATE TABLE "mail0_marketing_email_delivery" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text,
	"campaign" text NOT NULL,
	"email_key" text NOT NULL,
	"subject" text NOT NULL,
	"recipient_email" text NOT NULL,
	"recipient_email_normalized" text NOT NULL,
	"send_on_date" text NOT NULL,
	"scheduled_for" timestamp NOT NULL,
	"resend_id" text,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"sent_at" timestamp,
	CONSTRAINT "marketing_email_delivery_campaign_key_unique" UNIQUE("campaign","recipient_email_normalized","email_key"),
	CONSTRAINT "marketing_email_delivery_daily_limit_unique" UNIQUE("recipient_email_normalized","send_on_date")
);
--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ALTER COLUMN "bot_name" SET DEFAULT 'Note Taker';--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ALTER COLUMN "auto_join" SET DEFAULT false;--> statement-breakpoint
ALTER TABLE "mail0_user_settings" ALTER COLUMN "settings" SET DEFAULT '{"language":"en","timezone":"UTC","dynamicContent":false,"externalImages":true,"contextAboutYou":"","customPrompt":"","trustedSenders":[],"isOnboarded":false,"welcomeEmailSent":false,"colorTheme":"system","todusSignature":true,"autoRead":true,"defaultEmailAlias":"","categories":[{"id":"Important","name":"Important","searchValue":"IMPORTANT","order":0,"icon":"Lightning","isDefault":false},{"id":"All Mail","name":"All Mail","searchValue":"","order":1,"icon":"Mail","isDefault":true},{"id":"Unread","name":"Unread","searchValue":"UNREAD","order":5,"icon":"ScanEye","isDefault":false}],"undoSendEnabled":false,"imageCompression":"medium","animations":false,"assistantAutomationPolicy":{"autoSummarizeLongThreads":true,"suggestTasksFromEmail":true,"suggestEventsFromEmail":true,"autoDraftReplies":true,"smartReplyNudges":true,"smartDeadlineNudges":true,"assistantThreadActionsVisible":true,"briefingEnabled":true,"showHomeBriefing":true,"trackWaitingOnThreads":true,"peopleMemoryEnabled":true,"batchApprovalEnabled":false,"workdayStartHour":8,"workdayEndHour":18,"excludedSenderPatterns":[],"autoSendExperimentEnabled":false,"autoSendAllowedScenarios":["acknowledgment"],"autoSendQuietHours":{"startHour":22,"endHour":7}}}'::jsonb;--> statement-breakpoint
ALTER TABLE "mail0_connection" ADD COLUMN "color" text;--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ADD COLUMN "last_pruned_at" timestamp;--> statement-breakpoint
ALTER TABLE "mail0_assistant_briefing_snapshot" ADD CONSTRAINT "mail0_assistant_briefing_snapshot_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_assistant_feedback" ADD CONSTRAINT "mail0_assistant_feedback_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_assistant_open_loop" ADD CONSTRAINT "mail0_assistant_open_loop_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_assistant_open_loop" ADD CONSTRAINT "mail0_assistant_open_loop_source_meeting_id_mail0_meeting_id_fk" FOREIGN KEY ("source_meeting_id") REFERENCES "public"."mail0_meeting"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_assistant_open_loop" ADD CONSTRAINT "mail0_assistant_open_loop_source_task_id_mail0_task_id_fk" FOREIGN KEY ("source_task_id") REFERENCES "public"."mail0_task"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_assistant_person_memory" ADD CONSTRAINT "mail0_assistant_person_memory_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_assistant_prepared_action" ADD CONSTRAINT "mail0_assistant_prepared_action_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_assistant_prepared_action" ADD CONSTRAINT "mail0_assistant_prepared_action_source_meeting_id_mail0_meeting_id_fk" FOREIGN KEY ("source_meeting_id") REFERENCES "public"."mail0_meeting"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_assistant_workstream_memory" ADD CONSTRAINT "mail0_assistant_workstream_memory_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_marketing_email_delivery" ADD CONSTRAINT "mail0_marketing_email_delivery_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "assistant_briefing_snapshot_user_id_idx" ON "mail0_assistant_briefing_snapshot" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "assistant_briefing_snapshot_updated_at_idx" ON "mail0_assistant_briefing_snapshot" USING btree ("updated_at");--> statement-breakpoint
CREATE INDEX "assistant_feedback_user_id_idx" ON "mail0_assistant_feedback" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "assistant_feedback_target_idx" ON "mail0_assistant_feedback" USING btree ("target_type","target_id");--> statement-breakpoint
CREATE INDEX "assistant_open_loop_user_id_idx" ON "mail0_assistant_open_loop" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "assistant_open_loop_queue_idx" ON "mail0_assistant_open_loop" USING btree ("user_id","queue","status");--> statement-breakpoint
CREATE INDEX "assistant_open_loop_thread_idx" ON "mail0_assistant_open_loop" USING btree ("source_thread_id");--> statement-breakpoint
CREATE INDEX "assistant_open_loop_meeting_idx" ON "mail0_assistant_open_loop" USING btree ("source_meeting_id");--> statement-breakpoint
CREATE INDEX "assistant_open_loop_person_idx" ON "mail0_assistant_open_loop" USING btree ("user_id","person_email");--> statement-breakpoint
CREATE INDEX "assistant_open_loop_workstream_idx" ON "mail0_assistant_open_loop" USING btree ("user_id","workstream_key");--> statement-breakpoint
CREATE INDEX "assistant_open_loop_updated_at_idx" ON "mail0_assistant_open_loop" USING btree ("updated_at");--> statement-breakpoint
CREATE INDEX "assistant_person_memory_user_id_idx" ON "mail0_assistant_person_memory" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "assistant_person_memory_email_idx" ON "mail0_assistant_person_memory" USING btree ("user_id","email");--> statement-breakpoint
CREATE INDEX "assistant_person_memory_last_interaction_idx" ON "mail0_assistant_person_memory" USING btree ("last_interaction_at");--> statement-breakpoint
CREATE INDEX "assistant_prepared_action_user_id_idx" ON "mail0_assistant_prepared_action" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "assistant_prepared_action_status_idx" ON "mail0_assistant_prepared_action" USING btree ("user_id","status");--> statement-breakpoint
CREATE INDEX "assistant_prepared_action_thread_idx" ON "mail0_assistant_prepared_action" USING btree ("source_thread_id");--> statement-breakpoint
CREATE INDEX "assistant_prepared_action_meeting_idx" ON "mail0_assistant_prepared_action" USING btree ("source_meeting_id");--> statement-breakpoint
CREATE INDEX "assistant_prepared_action_workstream_idx" ON "mail0_assistant_prepared_action" USING btree ("user_id","workstream_key");--> statement-breakpoint
CREATE INDEX "assistant_prepared_action_updated_at_idx" ON "mail0_assistant_prepared_action" USING btree ("updated_at");--> statement-breakpoint
CREATE INDEX "assistant_workstream_memory_user_id_idx" ON "mail0_assistant_workstream_memory" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "assistant_workstream_memory_key_idx" ON "mail0_assistant_workstream_memory" USING btree ("user_id","key");--> statement-breakpoint
CREATE INDEX "assistant_workstream_memory_updated_at_idx" ON "mail0_assistant_workstream_memory" USING btree ("updated_at");--> statement-breakpoint
CREATE INDEX "marketing_email_delivery_user_id_idx" ON "mail0_marketing_email_delivery" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "marketing_email_delivery_send_on_date_idx" ON "mail0_marketing_email_delivery" USING btree ("send_on_date");--> statement-breakpoint
ALTER TABLE "mail0_account" ADD CONSTRAINT "account_provider_account_id_unique" UNIQUE("provider_id","account_id");