-- Doc starred flag for native/docs sidebar; default false for existing rows
ALTER TABLE "mail0_doc" ADD COLUMN IF NOT EXISTS "is_starred" boolean DEFAULT false NOT NULL;
