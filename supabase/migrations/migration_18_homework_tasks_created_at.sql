-- Add missing created_at column to homework_tasks
ALTER TABLE homework_tasks
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- Backfill existing rows
UPDATE homework_tasks SET created_at = now() WHERE created_at IS NULL;
