-- Add unique constraints to recall_media_id and recall_segment_id for idempotent webhook inserts
ALTER TABLE "mail0_meeting_media" ADD CONSTRAINT "mail0_meeting_media_recall_media_id_unique" UNIQUE("recall_media_id");
--> statement-breakpoint
ALTER TABLE "mail0_meeting_transcript" ADD CONSTRAINT "mail0_meeting_transcript_recall_segment_id_unique" UNIQUE("recall_segment_id");
