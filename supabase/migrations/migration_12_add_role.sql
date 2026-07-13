-- Migration 12: Add role to parents table for single-app-with-roles refactor.
--
-- As of v2, DoneFirst is a single Flutter app installed on both the
-- parent's phone and the kid's device. At signup, the user picks a
-- role: 'parent' (existing flow) or 'kid' (pairing-code flow). We
-- model this by adding a `role` column to the existing `parents`
-- table rather than renaming it, so every existing FK and RLS policy
-- continues to work unchanged.
--
-- Idempotent: safe to re-run. Uses ADD COLUMN IF NOT EXISTS, which
-- is supported on Postgres 9.6+. The CHECK constraint is added via
-- DO $$ so re-runs don't error if it already exists.
--
-- Apply this via the Supabase SQL Editor or
--   psql "$SUPABASE_DB_URL" -f migration_12_add_role.sql

ALTER TABLE parents
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'parent';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'parents_role_check'
  ) THEN
    ALTER TABLE parents
      ADD CONSTRAINT parents_role_check
      CHECK (role IN ('parent', 'kid'));
  END IF;
END
$$;

-- Helpful index. Most reads filter by role='parent' (the dashboard
-- queries), and the parent-side kid-device UI filters by role='kid'.
-- Smaller index than the full table; avoids seq scans on large
-- families.
CREATE INDEX IF NOT EXISTS parents_role_idx ON parents (role);

-- Update the kid-side companion tables' RLS so they accept rows
-- where the calling user has role='kid'. Today those tables are
-- service-role-only, but if we ever want a kid-side UI query to
-- work via the kid's JWT (e.g., "show me my devices" in the kid
-- app), we can extend this. For now: comment-only — the policies
-- from migration_11 are unchanged.
--
-- The kid app subscribes to homework_sessions via realtime filtered
-- by app_metadata.child_id, NOT by querying kid_devices directly,
-- so no RLS change is needed for the realtime path.

-- Sanity: every existing parent row should default to 'parent'
-- (NOT NULL DEFAULT). New rows created by claim-pairing will pass
-- role='kid' explicitly. Parents created via the parent-side auth
-- flow pass role='parent' explicitly.
UPDATE parents SET role = 'parent' WHERE role IS NULL;
