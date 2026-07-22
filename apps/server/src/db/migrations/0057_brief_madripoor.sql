CREATE TABLE "mail0_task_deletion" (
	"user_id" text NOT NULL,
	"task_id" text NOT NULL,
	"deleted_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "mail0_task_deletion_user_id_task_id_pk" PRIMARY KEY("user_id","task_id")
);
--> statement-breakpoint
ALTER TABLE "mail0_task_deletion" ADD CONSTRAINT "mail0_task_deletion_user_id_mail0_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."mail0_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "task_deletion_user_deleted_at_idx" ON "mail0_task_deletion" USING btree ("user_id","deleted_at");
