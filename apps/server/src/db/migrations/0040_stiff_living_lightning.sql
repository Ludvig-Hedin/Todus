CREATE TABLE "mail0_session_metadata" (
	"session_id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"device_label" text,
	"device_type" text,
	"os_name" text,
	"browser_name" text,
	"city" text,
	"region" text,
	"country" text,
	"last_seen_at" timestamp DEFAULT now() NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "mail0_session_metadata" ADD CONSTRAINT "mail0_session_metadata_session_id_mail0_session_id_fk" FOREIGN KEY ("session_id") REFERENCES "public"."mail0_session"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_session_metadata" ADD CONSTRAINT "mail0_session_metadata_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "session_metadata_user_id_idx" ON "mail0_session_metadata" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "session_metadata_updated_at_idx" ON "mail0_session_metadata" USING btree ("updated_at");
