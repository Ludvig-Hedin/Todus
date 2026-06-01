CREATE TABLE IF NOT EXISTS "mail0_slack_connection" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"team_id" text NOT NULL,
	"team_name" text NOT NULL,
	"team_domain" text,
	"team_icon" text,
	"enterprise_id" text,
	"slack_user_id" text NOT NULL,
	"slack_user_name" text,
	"slack_user_email" text,
	"access_token" text NOT NULL,
	"refresh_token" text,
	"token_type" text DEFAULT 'user' NOT NULL,
	"scope" text NOT NULL,
	"bot_user_id" text,
	"bot_access_token" text,
	"expires_at" timestamp,
	"send_enabled" boolean DEFAULT false NOT NULL,
	"color" text,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "slack_connection_user_team_user_unique" UNIQUE("user_id","team_id","slack_user_id")
);
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "mail0_slack_connection" ADD CONSTRAINT "mail0_slack_connection_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "slack_connection_user_id_idx" ON "mail0_slack_connection" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "slack_connection_team_id_idx" ON "mail0_slack_connection" USING btree ("team_id");
