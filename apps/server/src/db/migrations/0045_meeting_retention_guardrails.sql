ALTER TABLE "mail0_meet_integration" ADD COLUMN "last_pruned_at" timestamp;--> statement-breakpoint
DROP INDEX "meeting_recall_bot_id_idx";--> statement-breakpoint
DO $$
DECLARE
	duplicate_ids text;
BEGIN
	SELECT string_agg(dup.recall_bot_id, ', ' ORDER BY dup.recall_bot_id)
	INTO duplicate_ids
	FROM (
		SELECT "recall_bot_id"
		FROM "mail0_meeting"
		WHERE "recall_bot_id" IS NOT NULL
		GROUP BY "recall_bot_id"
		HAVING COUNT(*) > 1
	) AS dup;

	IF duplicate_ids IS NOT NULL THEN
		RAISE EXCEPTION
			'Cannot add constraint "mail0_meeting_recall_bot_id_unique": duplicate recall_bot_id values found in mail0_meeting: %',
			duplicate_ids;
	END IF;
END $$;
--> statement-breakpoint
ALTER TABLE "mail0_meeting" ADD CONSTRAINT "mail0_meeting_recall_bot_id_unique" UNIQUE("recall_bot_id");
