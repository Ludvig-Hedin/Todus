CREATE TABLE "mail0_folder_item" (
	"id" text PRIMARY KEY NOT NULL,
	"folder_id" text NOT NULL,
	"user_id" text NOT NULL,
	"item_type" text NOT NULL,
	"item_id" text NOT NULL,
	"metadata" jsonb,
	"position" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "folder_item_unique" UNIQUE("folder_id","item_type","item_id")
);
--> statement-breakpoint
ALTER TABLE "mail0_task_folder" ADD COLUMN "color" text;--> statement-breakpoint
ALTER TABLE "mail0_task_folder" ADD COLUMN "icon" text;--> statement-breakpoint
ALTER TABLE "mail0_task_folder" ADD COLUMN "position" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "mail0_task_folder" ADD COLUMN "updated_at" timestamp DEFAULT now() NOT NULL;--> statement-breakpoint
ALTER TABLE "mail0_folder_item" ADD CONSTRAINT "mail0_folder_item_folder_id_mail0_task_folder_id_fk" FOREIGN KEY ("folder_id") REFERENCES "public"."mail0_task_folder"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "mail0_folder_item" ADD CONSTRAINT "mail0_folder_item_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "folder_item_user_id_idx" ON "mail0_folder_item" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "folder_item_lookup_idx" ON "mail0_folder_item" USING btree ("item_type","item_id");