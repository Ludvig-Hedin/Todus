CREATE TABLE "mail0_group" (
	"id" text PRIMARY KEY NOT NULL,
	"owner_user_id" text NOT NULL,
	"name" text NOT NULL,
	"slug" text NOT NULL,
	"invite_token" text NOT NULL,
	"ai_mode" text DEFAULT 'mention' NOT NULL,
	"max_members" integer DEFAULT 20 NOT NULL,
	"deleted_at" timestamp,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "mail0_group_slug_unique" UNIQUE("slug"),
	CONSTRAINT "mail0_group_invite_token_unique" UNIQUE("invite_token")
);
--> statement-breakpoint
CREATE TABLE "mail0_group_member" (
	"group_id" text NOT NULL,
	"user_id" text NOT NULL,
	"role" text DEFAULT 'member' NOT NULL,
	"joined_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "mail0_group_member_group_id_user_id_pk" PRIMARY KEY("group_id","user_id")
);
--> statement-breakpoint
CREATE TABLE "mail0_group_message" (
	"id" text PRIMARY KEY NOT NULL,
	"group_id" text NOT NULL,
	"sender_user_id" text,
	"sender_type" text NOT NULL,
	"content" text NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "mail0_shared_conversation" (
	"id" text PRIMARY KEY NOT NULL,
	"owner_user_id" text NOT NULL,
	"conversation_id" text NOT NULL,
	"slug" text NOT NULL,
	"title" text DEFAULT '' NOT NULL,
	"password_hash" text,
	"password_salt" text,
	"expires_at" timestamp,
	"revoked_at" timestamp,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "mail0_shared_conversation_slug_unique" UNIQUE("slug")
);
--> statement-breakpoint
ALTER TABLE "mail0_ai_conversation" ADD COLUMN "folder_id" text;--> statement-breakpoint
ALTER TABLE "mail0_group" ADD CONSTRAINT "mail0_group_owner_user_id_mail0_user_id_fk" FOREIGN KEY ("owner_user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_group_member" ADD CONSTRAINT "mail0_group_member_group_id_mail0_group_id_fk" FOREIGN KEY ("group_id") REFERENCES "public"."mail0_group"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_group_member" ADD CONSTRAINT "mail0_group_member_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_group_message" ADD CONSTRAINT "mail0_group_message_group_id_mail0_group_id_fk" FOREIGN KEY ("group_id") REFERENCES "public"."mail0_group"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_group_message" ADD CONSTRAINT "mail0_group_message_sender_user_id_mail0_user_id_fk" FOREIGN KEY ("sender_user_id") REFERENCES "public"."mail0_user"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_shared_conversation" ADD CONSTRAINT "mail0_shared_conversation_owner_user_id_mail0_user_id_fk" FOREIGN KEY ("owner_user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_shared_conversation" ADD CONSTRAINT "mail0_shared_conversation_conversation_id_mail0_ai_conversation_id_fk" FOREIGN KEY ("conversation_id") REFERENCES "public"."mail0_ai_conversation"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "group_owner_idx" ON "mail0_group" USING btree ("owner_user_id");--> statement-breakpoint
-- group_slug_idx and group_invite_token_idx removed: redundant with the UNIQUE constraints above
CREATE INDEX "group_deleted_at_idx" ON "mail0_group" USING btree ("deleted_at");--> statement-breakpoint
CREATE INDEX "group_member_user_id_idx" ON "mail0_group_member" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "group_message_group_id_idx" ON "mail0_group_message" USING btree ("group_id");--> statement-breakpoint
CREATE INDEX "group_message_group_created_idx" ON "mail0_group_message" USING btree ("group_id","created_at");--> statement-breakpoint
CREATE INDEX "shared_conversation_owner_idx" ON "mail0_shared_conversation" USING btree ("owner_user_id");--> statement-breakpoint
-- shared_conversation_slug_idx removed: redundant with the UNIQUE constraint above
CREATE INDEX "shared_conversation_conversation_id_idx" ON "mail0_shared_conversation" USING btree ("conversation_id");--> statement-breakpoint
ALTER TABLE "mail0_ai_conversation" ADD CONSTRAINT "mail0_ai_conversation_folder_id_mail0_task_folder_id_fk" FOREIGN KEY ("folder_id") REFERENCES "public"."mail0_task_folder"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "ai_conversation_folder_id_idx" ON "mail0_ai_conversation" USING btree ("folder_id");