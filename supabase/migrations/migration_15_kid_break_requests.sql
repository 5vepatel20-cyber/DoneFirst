-- Migration 15: kid-readable break_requests + break lifecycle columns.
--
-- Goal: when a parent approves a break for a session, the kid-side
-- app needs to learn about it via Supabase realtime so it can
-- release the lock for the duration of the break. Today the parent
-- only updates homework_sessions.status; break_requests has no
-- timeline, so the kid stays locked the entire time the parent's
-- BreakTimer counts down. The break is honoured on the parent's
-- phone but not the kid's.
--
-- This migration does three things:
--
--   1. Adds started_at / ended_at columns to break_requests so the
--      kid can compute "am I currently on a break?" from the latest
--      row. The parent still drives the lifecycle (parent app calls
--      BreakService.approveBreak / endBreak / cancelBreak) — the
--      columns just record the timeline.
--
--   2. Adds a kid-readable SELECT policy on break_requests. The
--      parent policy is FOR ALL keyed on the linked session's
--      parent_id, which the kid JWT doesn't satisfy. Without a
--      separate SELECT policy, the kid's realtime subscription
--      gets filtered to zero rows by RLS and the kid app silently
--      never sees a break approved.
--
--      The kid's filter lives in the JWT's app_metadata custom
--      claim (see claim-pairing Edge Function). RLS uses
--      auth.jwt() -> 'app_metadata' ->> 'child_id' to scope the
--      kid's view to their own session.
--
--   3. Adds a status check constraint listing the four valid
--      statuses. The previous column was freeform text; the kid
--      realtime service now branches on exact values.
--
-- Idempotent: safe to re-run. ADD COLUMN IF NOT EXISTS, CREATE /
-- DROP POLICY IF EXISTS, DO $$ for the constraint.

ALTER TABLE break_requests
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ;

ALTER TABLE break_requests
  ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;

-- Helpful index for the kid's "is the latest break active?" query.
-- We don't index ended_at because the typical lookup is
-- ORDER BY started_at DESC LIMIT 1, which uses this index.
CREATE INDEX IF NOT EXISTS break_requests_session_id_started_at_idx
  ON break_requests (session_id, started_at DESC NULLS LAST);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'break_requests_status_check'
  ) THEN
    ALTER TABLE break_requests
      ADD CONSTRAINT break_requests_status_check
      CHECK (status IN ('pending', 'approved', 'denied', 'completed', 'cancelled'));
  END IF;
END
$$;

-- Kid-readable SELECT policy. Lets the kid-side app's realtime
-- subscription (filtered by session_id in the next migration /
-- Dart change) actually receive break_request events.
DROP POLICY IF EXISTS "Kids can read their own session breaks" ON break_requests;
CREATE POLICY "Kids can read their own session breaks"
  ON break_requests FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM homework_sessions hs
      WHERE hs.id = break_requests.session_id
      AND hs.child_id = (
        (auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid
      )
    )
  );

-- Sanity: make sure no break_requests rows already have a status
-- that the new CHECK would reject. If they do, the ALTER TABLE
-- will fail and the migration is stuck — better to surface that
-- here with a clear message than to ship a broken constraint.
DO $$
DECLARE
  bad_count INTEGER;
BEGIN
  SELECT count(*) INTO bad_count FROM break_requests
    WHERE status NOT IN ('pending', 'approved', 'denied', 'completed', 'cancelled');
  IF bad_count > 0 THEN
    RAISE EXCEPTION
      'break_requests contains % row(s) with a status outside the allowed set; '
      'fix them before re-running.', bad_count;
  END IF;
END
$$;
