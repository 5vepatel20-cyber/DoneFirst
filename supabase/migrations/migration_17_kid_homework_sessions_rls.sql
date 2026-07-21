-- Migration 17: Kid-side SELECT on homework_sessions.
--
-- The kid app reads homework_sessions via both a bootstrap query
-- and a realtime Postgres-Changes subscription, filtering by
-- child_id. The existing RLS policy ("Parents can manage sessions")
-- only allows parent_id = auth.uid(), which blocks kid JWTs whose
-- identity lives in app_metadata.child_id.
--
-- This migration adds a permissive SELECT policy so kids can read
-- their own session rows. It does NOT grant INSERT / UPDATE /
-- DELETE — only the parent (or service_role) may mutate sessions.

-- Idempotent: safe to re-run
DROP POLICY IF EXISTS "Kid can read own sessions" ON homework_sessions;

CREATE POLICY "Kid can read own sessions"
  ON homework_sessions
  FOR SELECT
  TO authenticated
  USING (
    child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
  );
