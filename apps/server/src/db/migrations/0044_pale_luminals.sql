CREATE TABLE "mail0_doc" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"workspace_id" text,
	"parent_id" text,
	"title" text DEFAULT 'Untitled' NOT NULL,
	"content" jsonb,
	"content_text" text,
	"emoji" text,
	"order" integer DEFAULT 0 NOT NULL,
	"linked_thread_id" text,
	"linked_event_id" text,
	"linked_task_id" text,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "mail0_doc_workspace" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"name" text NOT NULL,
	"emoji" text,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
DROP INDEX "meet_integration_user_id_idx";--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ALTER COLUMN "bot_name" SET DEFAULT 'Notetaker';--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ALTER COLUMN "auto_join" SET DEFAULT true;--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ADD COLUMN "auto_generate_summary" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ADD COLUMN "summary_language" text DEFAULT 'en' NOT NULL;--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ADD COLUMN "exclude_all_day" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ADD COLUMN "minimum_duration_minutes" integer DEFAULT 5 NOT NULL;--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ADD COLUMN "notify_on_recording_start" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ADD COLUMN "notify_on_recap_ready" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "mail0_meet_integration" ADD COLUMN "auto_delete_days" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "mail0_doc" ADD CONSTRAINT "mail0_doc_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_doc" ADD CONSTRAINT "mail0_doc_workspace_id_mail0_doc_workspace_id_fk" FOREIGN KEY ("workspace_id") REFERENCES "public"."mail0_doc_workspace"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_doc" ADD CONSTRAINT "mail0_doc_parent_id_mail0_doc_id_fk" FOREIGN KEY ("parent_id") REFERENCES "public"."mail0_doc"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_doc_workspace" ADD CONSTRAINT "mail0_doc_workspace_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "doc_user_id_idx" ON "mail0_doc" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "doc_workspace_id_idx" ON "mail0_doc" USING btree ("workspace_id");--> statement-breakpoint
CREATE INDEX "doc_parent_id_idx" ON "mail0_doc" USING btree ("parent_id");--> statement-breakpoint
CREATE INDEX "doc_updated_at_idx" ON "mail0_doc" USING btree ("updated_at");--> statement-breakpoint
CREATE INDEX "doc_workspace_user_id_idx" ON "mail0_doc_workspace" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "group_message_sender_user_id_idx" ON "mail0_group_message" USING btree ("sender_user_id");--> statement-breakpoint
CREATE INDEX "meeting_integration_id_idx" ON "mail0_meeting" USING btree ("integration_id");--> statement-breakpoint
DO $$
DECLARE
	duplicate_ids text;
BEGIN
	SELECT string_agg(dup.recall_media_id, ', ' ORDER BY dup.recall_media_id)
	INTO duplicate_ids
	FROM (
		SELECT "recall_media_id"
		FROM "mail0_meeting_media"
		WHERE "recall_media_id" IS NOT NULL
		GROUP BY "recall_media_id"
		HAVING COUNT(*) > 1
	) AS dup;

	IF duplicate_ids IS NOT NULL THEN
		RAISE EXCEPTION
			'Cannot add constraint "mail0_meeting_media_recall_media_id_unique": duplicate recall_media_id values found in mail0_meeting_media: %',
			duplicate_ids;
	END IF;
END $$;
--> statement-breakpoint
ALTER TABLE "mail0_meeting_media" ADD CONSTRAINT "mail0_meeting_media_recall_media_id_unique" UNIQUE("recall_media_id");--> statement-breakpoint
DO $$
DECLARE
	duplicate_ids text;
BEGIN
	SELECT string_agg(dup.recall_segment_id, ', ' ORDER BY dup.recall_segment_id)
	INTO duplicate_ids
	FROM (
		SELECT "recall_segment_id"
		FROM "mail0_meeting_transcript"
		WHERE "recall_segment_id" IS NOT NULL
		GROUP BY "recall_segment_id"
		HAVING COUNT(*) > 1
	) AS dup;

	IF duplicate_ids IS NOT NULL THEN
		RAISE EXCEPTION
			'Cannot add constraint "mail0_meeting_transcript_recall_segment_id_unique": duplicate recall_segment_id values found in mail0_meeting_transcript: %',
			duplicate_ids;
	END IF;
END $$;
--> statement-breakpoint
ALTER TABLE "mail0_meeting_transcript" ADD CONSTRAINT "mail0_meeting_transcript_recall_segment_id_unique" UNIQUE("recall_segment_id");
