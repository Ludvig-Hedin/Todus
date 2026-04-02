-- Add unique constraints to recall_media_id and recall_segment_id for idempotent webhook inserts
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
ALTER TABLE "mail0_meeting_media" ADD CONSTRAINT "mail0_meeting_media_recall_media_id_unique" UNIQUE("recall_media_id");
--> statement-breakpoint
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
