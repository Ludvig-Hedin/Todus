WITH ranked_accounts AS (
	SELECT
		"id",
		row_number() OVER (
			PARTITION BY "provider_id", "account_id"
			ORDER BY "updated_at" DESC NULLS LAST, "created_at" DESC NULLS LAST, "id" DESC
		) AS row_number
	FROM "mail0_account"
)
DELETE FROM "mail0_account" AS account
USING ranked_accounts
WHERE account."id" = ranked_accounts."id"
  AND ranked_accounts.row_number > 1;
--> statement-breakpoint
ALTER TABLE "mail0_account"
ADD CONSTRAINT "mail0_account_provider_account_id_unique" UNIQUE("provider_id","account_id");
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
	"sent_at" timestamp
);
--> statement-breakpoint
ALTER TABLE "mail0_marketing_email_delivery"
ADD CONSTRAINT "mail0_marketing_email_delivery_user_id_mail0_user_id_fk"
FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
ALTER TABLE "mail0_marketing_email_delivery"
ADD CONSTRAINT "mail0_marketing_email_delivery_campaign_key_unique"
UNIQUE("campaign","recipient_email_normalized","email_key");
--> statement-breakpoint
ALTER TABLE "mail0_marketing_email_delivery"
ADD CONSTRAINT "mail0_marketing_email_delivery_daily_limit_unique"
UNIQUE("recipient_email_normalized","send_on_date");
--> statement-breakpoint
CREATE INDEX "marketing_email_delivery_user_id_idx"
ON "mail0_marketing_email_delivery" USING btree ("user_id");
--> statement-breakpoint
CREATE INDEX "marketing_email_delivery_send_on_date_idx"
ON "mail0_marketing_email_delivery" USING btree ("send_on_date");
