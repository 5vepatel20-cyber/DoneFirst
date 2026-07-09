-- Retention / cleanup jobs (Migration 10)
--
-- COPPA + GDPR-K: collect minimum data, retain for minimum time.
-- The Mistral verification log is operational telemetry used for
-- the daily-quota check and (soon) in-app usage stats. It does
-- not need to be retained longer than 30 days for the app's own
-- purposes; longer retention would be hard to justify if audited.
--
-- Run this in the Supabase SQL Editor AFTER applying
-- schema_migrations.sql. The functions are created safely
-- (CREATE OR REPLACE), and the schedule is added only if the
-- pg_cron extension is already enabled (Supabase projects have
-- it disabled by default — see comments below before enabling).
--
-- ============================================================
--   1. Function: purge logs older than 30 days
-- ============================================================

CREATE OR REPLACE FUNCTION purge_old_mistral_logs(
  older_than INTERVAL DEFAULT INTERVAL '30 days'
) RETURNS INTEGER AS $$
DECLARE
  deleted INTEGER;
BEGIN
  WITH deleted_rows AS (
    DELETE FROM mistral_verification_log
    WHERE called_at < now() - older_than
    RETURNING 1
  )
  SELECT count(*) INTO deleted FROM deleted_rows;
  RETURN deleted;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION purge_old_mistral_logs IS
  'Deletes Mistral verification log rows older than the given '
  'interval (default 30 days). Returns the number of rows deleted.';

-- ============================================================
--   2. Function: count orphan proof-photos in Storage
-- ============================================================
--
-- Proof photos are uploaded to the 'proof-photos' bucket as
-- {child_id}/{proof_id}/{filename}. When a proof_submissions row
-- is deleted, the underlying storage object is not auto-removed
-- (Postgres DELETE on a TEXT[] column doesn't cascade into
-- Storage). This function returns storage objects whose path
-- references a proof_id that no longer exists in
-- proof_submissions. It's read-only — actually deleting the
-- objects needs the storage admin API, not raw SQL.

CREATE OR REPLACE FUNCTION find_orphan_proof_photos()
RETURNS TABLE (storage_path TEXT, missing_proof_id UUID) AS $$
  -- proof-photos paths follow the pattern {child_id}/{proof_id}/{filename}
  -- proof_id segments can be extracted by splitting on '/' and taking
  -- element 2. Casting that segment to UUID filters out non-proof
  -- objects (e.g. avatars) and rows whose middle segment isn't a UUID.
  WITH parsed AS (
    SELECT
      name::TEXT AS storage_path,
      split_part(name, '/', 2)::UUID AS proof_id
    FROM storage.objects
    WHERE bucket_id = 'proof-photos'
  )
  SELECT p.storage_path, p.proof_id
  FROM parsed p
  LEFT JOIN proof_submissions ps ON ps.id = p.proof_id
  WHERE ps.id IS NULL;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION find_orphan_proof_photos IS
  'Returns proof-photos storage objects whose referenced '
  'proof_submissions row no longer exists. Read-only — use the '
  'Supabase dashboard Storage UI or admin API to actually delete '
  'them in batches.';

-- ============================================================
--   3. Optional: schedule the purge via pg_cron
-- ============================================================
--
-- pg_cron is NOT enabled on Supabase free tier by default.
-- On Pro plans it can be enabled in Dashboard -> Database ->
-- Extensions. If you enable it, the following schedules the
-- purge to run daily at 04:00 UTC.
--
-- If you skip pg_cron, you can invoke the purge function
-- manually from the SQL Editor:
--   SELECT purge_old_mistral_logs();
--
-- Or from the Supabase scheduled Edge Function / cron worker UI.
--
-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- SELECT cron.schedule(
--   'purge-mistral-logs-daily',
--   '0 4 * * *',  -- 04:00 UTC every day
--   $$SELECT purge_old_mistral_logs();$$
-- );

-- ============================================================
--   4. Sanity check: row counts before / after
-- ============================================================
--
-- Run these manually to verify the purge worked:
--
-- SELECT count(*) AS total_rows FROM mistral_verification_log;
-- SELECT count(*) AS rows_last_30d FROM mistral_verification_log
--   WHERE called_at >= now() - INTERVAL '30 days';
-- SELECT count(*) AS orphan_storage_objects FROM find_orphan_proof_photos();
