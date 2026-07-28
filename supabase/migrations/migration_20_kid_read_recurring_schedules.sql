-- Migration 20: Kid-side SELECT on recurring_schedules.
--
-- The kid's Today dashboard (lib/screens/kid/today_screen.dart) shows
-- a "Next session" card built from ScheduleService.getSchedules().
-- Every policy on recurring_schedules is parent-scoped, and a kid JWT
-- carries its identity in app_metadata.child_id — so the read returned
-- zero rows for every kid. RLS filters rather than errors, so this was
-- invisible: the card just said "Nothing scheduled yet — your parent
-- can set up a homework routine" forever, including for families who
-- had set one up.
--
-- SELECT only. Schedules stay parent-owned; the kid never writes them.
--
-- Mirrors migration_17's "Kid can read own sessions".
-- Idempotent: safe to re-run.

DROP POLICY IF EXISTS "Kid can read own schedules" ON recurring_schedules;

CREATE POLICY "Kid can read own schedules"
  ON recurring_schedules
  FOR SELECT
  TO authenticated
  USING (
    child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
  );
