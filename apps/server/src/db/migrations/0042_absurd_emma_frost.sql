CREATE TABLE "mail0_meet_integration" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"bot_name" text DEFAULT 'Note Taker' NOT NULL,
	"is_enabled" boolean DEFAULT true NOT NULL,
	"auto_join" boolean DEFAULT false NOT NULL,
	"join_early_minutes" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "mail0_meet_integration_user_id_unique" UNIQUE("user_id")
);
--> statement-breakpoint
CREATE TABLE "mail0_meeting" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"integration_id" text,
	"google_event_id" text,
	"calendar_id" text,
	"title" text NOT NULL,
	"description" text,
	"meet_url" text NOT NULL,
	"starts_at" timestamp NOT NULL,
	"ends_at" timestamp,
	"recall_bot_id" text,
	"recall_meeting_id" text,
	"bot_joined_at" timestamp,
	"bot_left_at" timestamp,
	"status" text DEFAULT 'scheduled' NOT NULL,
	"error_message" text,
	"participants" jsonb,
	"ai_summary" text,
	"action_items" jsonb,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "mail0_meeting_media" (
	"id" text PRIMARY KEY NOT NULL,
	"meeting_id" text NOT NULL,
	"media_type" text NOT NULL,
	"recall_media_id" text,
	"url" text NOT NULL,
	"file_name" text,
	"file_size" integer,
	"duration" integer,
	"is_ready" boolean DEFAULT false NOT NULL,
	"ready_at" timestamp,
	"metadata" jsonb,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "mail0_meeting_transcript" (
	"id" text PRIMARY KEY NOT NULL,
	"meeting_id" text NOT NULL,
	"start_time" integer NOT NULL,
	"end_time" integer,
	"speaker_name" text NOT NULL,
	"speaker_id" text,
	"text" text NOT NULL,
	"confidence" text,
	"is_from_realtime" boolean DEFAULT false NOT NULL,
	"recall_segment_id" text,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "mail0_user_settings" ALTER COLUMN "settings" SET DEFAULT '{"language":"en","timezone":"UTC","dynamicContent":false,"externalImages":true,"contextAboutYou":"","customPrompt":"","trustedSenders":[],"isOnboarded":false,"welcomeEmailSent":false,"colorTheme":"system","todusSignature":true,"autoRead":true,"defaultEmailAlias":"","categories":[{"id":"Important","name":"Important","searchValue":"IMPORTANT","order":0,"icon":"Lightning","isDefault":false},{"id":"All Mail","name":"All Mail","searchValue":"","order":1,"icon":"Mail","isDefault":true},{"id":"Unread","name":"Unread","searchValue":"UNREAD","order":5,"icon":"ScanEye","isDefault":false}],"undoSendEnabled":false,"imageCompression":"medium","animations":false,"assistantAutomationPolicy":{"autoSummarizeLongThreads":true,"suggestTasksFromEmail":true,"suggestEventsFromEmail":true,"autoDraftReplies":true,"smartReplyNudges":true,"smartDeadlineNudges":true,"assistantThreadActionsVisible":true,"autoSendExperimentEnabled":false,"autoSendAllowedScenarios":["acknowledgment"],"autoSendQuietHours":{"startHour":22,"endHour":7}}}'::jsonb;--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ADD CONSTRAINT "mail0_meet_integration_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_meeting" ADD CONSTRAINT "mail0_meeting_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_meeting" ADD CONSTRAINT "mail0_meeting_integration_id_mail0_meet_integration_id_fk" FOREIGN KEY ("integration_id") REFERENCES "public"."mail0_meet_integration"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_meeting_media" ADD CONSTRAINT "mail0_meeting_media_meeting_id_mail0_meeting_id_fk" FOREIGN KEY ("meeting_id") REFERENCES "public"."mail0_meeting"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_meeting_transcript" ADD CONSTRAINT "mail0_meeting_transcript_meeting_id_mail0_meeting_id_fk" FOREIGN KEY ("meeting_id") REFERENCES "public"."mail0_meeting"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "meet_integration_user_id_idx" ON "mail0_meet_integration" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "meeting_user_id_idx" ON "mail0_meeting" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "meeting_status_idx" ON "mail0_meeting" USING btree ("status");--> statement-breakpoint
CREATE INDEX "meeting_recall_bot_id_idx" ON "mail0_meeting" USING btree ("recall_bot_id");--> statement-breakpoint
CREATE INDEX "meeting_starts_at_idx" ON "mail0_meeting" USING btree ("starts_at");--> statement-breakpoint
CREATE INDEX "meeting_user_status_idx" ON "mail0_meeting" USING btree ("user_id","status");--> statement-breakpoint
CREATE INDEX "meeting_google_event_idx" ON "mail0_meeting" USING btree ("user_id","google_event_id");--> statement-breakpoint
CREATE INDEX "meeting_media_meeting_id_idx" ON "mail0_meeting_media" USING btree ("meeting_id");--> statement-breakpoint
CREATE INDEX "meeting_media_type_idx" ON "mail0_meeting_media" USING btree ("media_type");--> statement-breakpoint
CREATE INDEX "meeting_transcript_meeting_id_idx" ON "mail0_meeting_transcript" USING btree ("meeting_id");--> statement-breakpoint
CREATE INDEX "meeting_transcript_meeting_time_idx" ON "mail0_meeting_transcript" USING btree ("meeting_id","start_time");