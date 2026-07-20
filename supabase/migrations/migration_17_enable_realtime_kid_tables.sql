-- Migration 17: enable Realtime for the tables the kid app subscribes to.
--
-- ROOT CAUSE this fixes
-- ---------------------
-- The kid app's lock-state machine (KidRealtimeService) opens a
-- postgres_changes subscription on:
--   * homework_sessions  (filtered by child_id)
--   * break_requests     (filtered by session_id)
-- If those tables are not members of the `supabase_realtime`
-- publication, the Realtime server rejects the subscription with:
--   "Unable to subscribe to changes with given parameters. Please
--    check Realtime is enabled for the given connect parameters"
-- KidRealtimeService then reports channelError -> KidLockState.waiting,
-- stranding the kid on the WaitingScreen ("Can't reach the parent
-- app") forever.
--
-- migration_14 enabled kid_device_events, and migration_12's comment
-- *claims* homework_sessions is realtime-subscribed, but the
-- ALTER PUBLICATION was never actually written for these two tables,
-- so kid realtime has never worked. This migration backfills it.

-- REPLICA IDENTITY FULL so child_id / session_id are present in the
-- WAL for UPDATE and DELETE events too. Without this, Realtime's `eq`
-- filters (child_id / session_id) can't match on those operations and
-- the kid would miss session-end and break-update events even once the
-- table is in the publication.
ALTER TABLE public.homework_sessions REPLICA IDENTITY FULL;
ALTER TABLE public.break_requests REPLICA IDENTITY FULL;

-- Add both tables to the realtime publication. Guarded via
-- pg_publication_tables so re-running the migration (or a table
-- already enabled by hand in the dashboard) is a safe no-op rather
-- than a "table is already member of publication" error.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'homework_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.homework_sessions;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'break_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.break_requests;
  END IF;
END $$;
