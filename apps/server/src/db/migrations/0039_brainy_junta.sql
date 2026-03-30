CREATE TABLE "mail0_ai_conversation" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"title" text DEFAULT '' NOT NULL,
	"messages" jsonb DEFAULT '[]' NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "mail0_task" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"title" text NOT NULL,
	"description" text DEFAULT '',
	"status" text DEFAULT 'todo' NOT NULL CONSTRAINT "chk_mail0_task_status" CHECK ("status" IN ('todo', 'doing', 'done')),
	"priority" text DEFAULT 'none' NOT NULL CONSTRAINT "chk_mail0_task_priority" CHECK ("priority" IN ('none', 'low', 'medium', 'high')),
	"due_date" timestamp,
	"folder_id" text,
	"reminder_identifier" text,
	"email_thread_id" text,
	"event_id" text,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "mail0_task_folder" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"name" text NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE OR REPLACE FUNCTION update_updated_at_column() RETURNS trigger AS $$
BEGIN
	NEW.updated_at = now();
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;
--> statement-breakpoint
CREATE TRIGGER "update_mail0_ai_conversation_updated_at" BEFORE UPDATE ON "mail0_ai_conversation" FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
--> statement-breakpoint
CREATE TRIGGER "update_mail0_task_updated_at" BEFORE UPDATE ON "mail0_task" FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
--> statement-breakpoint
ALTER TABLE "mail0_ai_conversation" ADD CONSTRAINT "mail0_ai_conversation_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_task" ADD CONSTRAINT "mail0_task_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_task" ADD CONSTRAINT "mail0_task_folder_id_mail0_task_folder_id_fk" FOREIGN KEY ("folder_id") REFERENCES "public"."mail0_task_folder"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_task_folder" ADD CONSTRAINT "mail0_task_folder_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_oauth_application" ADD CONSTRAINT "mail0_oauth_application_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_oauth_access_token" ADD CONSTRAINT "mail0_oauth_access_token_client_id_mail0_oauth_application_client_id_fk" FOREIGN KEY ("client_id") REFERENCES "public"."mail0_oauth_application"("client_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_oauth_access_token" ADD CONSTRAINT "mail0_oauth_access_token_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_oauth_consent" ADD CONSTRAINT "mail0_oauth_consent_client_id_mail0_oauth_application_client_id_fk" FOREIGN KEY ("client_id") REFERENCES "public"."mail0_oauth_application"("client_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_oauth_consent" ADD CONSTRAINT "mail0_oauth_consent_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_writing_style_matrix" RENAME COLUMN "connectionId" TO "connection_id";--> statement-breakpoint
ALTER TABLE "mail0_writing_style_matrix" RENAME COLUMN "numMessages" TO "num_messages";--> statement-breakpoint
ALTER TABLE "mail0_writing_style_matrix" RENAME COLUMN "updatedAt" TO "updated_at";--> statement-breakpoint
ALTER TABLE "mail0_writing_style_matrix" RENAME CONSTRAINT "mail0_writing_style_matrix_connectionId_pk" TO "mail0_writing_style_matrix_connection_id_pk";--> statement-breakpoint
ALTER TABLE "mail0_writing_style_matrix" RENAME CONSTRAINT "mail0_writing_style_matrix_connectionId_mail0_connection_id_fk" TO "mail0_writing_style_matrix_connection_id_mail0_connection_id_fk";--> statement-breakpoint
CREATE INDEX "ai_conversation_user_id_idx" ON "mail0_ai_conversation" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "ai_conversation_updated_at_idx" ON "mail0_ai_conversation" USING btree ("updated_at");--> statement-breakpoint
CREATE INDEX "task_user_id_idx" ON "mail0_task" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "task_folder_id_idx" ON "mail0_task" USING btree ("folder_id");--> statement-breakpoint
CREATE INDEX "task_status_idx" ON "mail0_task" USING btree ("status");--> statement-breakpoint
CREATE INDEX "task_due_date_idx" ON "mail0_task" USING btree ("due_date");--> statement-breakpoint
CREATE INDEX "task_user_status_idx" ON "mail0_task" USING btree ("user_id","status");--> statement-breakpoint
CREATE INDEX "task_email_thread_id_idx" ON "mail0_task" USING btree ("email_thread_id");--> statement-breakpoint
CREATE INDEX "task_event_id_idx" ON "mail0_task" USING btree ("event_id");--> statement-breakpoint
CREATE INDEX "task_folder_user_id_idx" ON "mail0_task_folder" USING btree ("user_id");
