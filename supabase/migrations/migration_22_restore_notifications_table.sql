-- Migration 22: restore the `notifications` table the app actually uses.
--
-- WHY THIS EXISTS
--
-- `notifications` was created by hand in the Supabase dashboard and
-- never had DDL in this repo, so nothing pinned its shape. On
-- 2026-07-29 the live table came back with a completely different
-- schema:
--
--     id, user_id, type, created_at, is_read, message, actor_id
--
-- That is a generic social-feed notification table (`actor_id` =
-- who did the thing, `user_id` = who receives it). DoneFirst has no
-- such concept. The same database also grew a `public.user_cars`
-- table, which belongs to no part of this product — so the most
-- likely explanation is that an unrelated project's schema was
-- applied to this project by mistake, dropping and recreating
-- `notifications` on the way through and taking all 41 rows with it.
--
-- The app has always written and read these columns instead:
--
--     id, parent_id, child_id, type, title, body, read, created_at
--
-- (see NotificationService, AppNotification.fromMap, and the
-- delete-account Edge Function, which deletes by parent_id). With
-- the live table in its foreign shape every one of those queries
-- fails with 42703, and because ParentDashboard._loadAll fans its
-- reads out through a single Future.wait, one 42703 aborted the
-- whole dashboard load: the banner read "column
-- notifications.parent_id does not exist" and, as a side effect of
-- never reaching the per-child section, a correctly-paired kid
-- device rendered as "No device paired".
--
-- WHAT THIS DOES
--
--   1. If a `notifications` table exists but does not have
--      `parent_id`, rename it aside rather than dropping it. It is
--      not ours, it may belong to whoever ran the other schema, and
--      a rename is reversible where a DROP is not. Nothing in this
--      product reads the renamed table.
--   2. Create `notifications` in the shape the app expects, with the
--      DDL living in the repo this time so it can be rebuilt from
--      source.
--   3. Grant the API roles table access. RLS is what restricts rows;
--      without the grant every request fails outright.
--   4. RLS: parents own their inbox. Kids get INSERT only — they
--      raise 'proof_submitted' and 'break_requested' from their own
--      device (ProofCaptureScreen, KidHomeScreen) — and cannot read
--      the parent's inbox back.
--   5. Re-add the table to the realtime publication so
--      RealtimeService's bell badge keeps updating live.
--
-- Idempotent: re-running is a no-op.

-- 1. Move a foreign `notifications` out of the way.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'notifications'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'notifications'
      AND column_name = 'parent_id'
  ) THEN
    ALTER TABLE public.notifications
      RENAME TO notifications_foreign_20260729;

    -- RENAME TO moves the table but leaves its constraints and
    -- indexes under their original names, so `notifications_pkey`
    -- would still be taken and the table created below would silently
    -- end up with a primary key called `notifications_pkey1`. Not
    -- fatal, but the next person to read this schema deserves better.
    IF EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'notifications_pkey'
    ) THEN
      ALTER TABLE public.notifications_foreign_20260729
        RENAME CONSTRAINT notifications_pkey TO notifications_foreign_20260729_pkey;
    END IF;

    -- It also stays in the realtime publication under the new name,
    -- streaming WAL for a table nothing in this product reads.
    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'notifications_foreign_20260729'
    ) THEN
      ALTER PUBLICATION supabase_realtime
        DROP TABLE public.notifications_foreign_20260729;
    END IF;
  END IF;
END $$;

-- 2. The table the app expects.
CREATE TABLE IF NOT EXISTS public.notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id  UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  child_id   UUID REFERENCES public.children (id) ON DELETE CASCADE,
  -- Free text on purpose. The known values are 'proof_submitted',
  -- 'break_requested', 'session_complete' and 'session_auto_lift',
  -- but NotificationPreferencesService already treats an unknown
  -- type as enabled, and a CHECK here would turn "someone shipped a
  -- new notification type" into a hard insert failure on the kid's
  -- device mid-session.
  type       TEXT NOT NULL,
  title      TEXT NOT NULL,
  body       TEXT,
  read       BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- getNotifications / getUnreadNotifications / getUnreadCount all
-- filter on parent_id and order by created_at desc; the unread
-- variants add read = false.
CREATE INDEX IF NOT EXISTS notifications_parent_created_idx
  ON public.notifications (parent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_parent_unread_idx
  ON public.notifications (parent_id)
  WHERE read = FALSE;

-- 3. Table-level access for the API roles.
--
-- Supabase normally hands this out through ALTER DEFAULT PRIVILEGES,
-- but that only fires for the role the defaults are attached to — run
-- this migration from a different role (or a project whose defaults
-- were never set up) and PostgREST answers every request with
-- "permission denied for table notifications", taking the whole
-- notification centre down. Granting explicitly costs nothing and
-- removes the dependency: RLS above is what actually restricts rows,
-- not the absence of a GRANT.
DO $$
DECLARE
  api_role TEXT;
BEGIN
  FOREACH api_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = api_role) THEN
      EXECUTE format(
        'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.notifications TO %I',
        api_role
      );
    END IF;
  END LOOP;
END $$;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- 4a. Parents own their own inbox, end to end (read, mark read,
-- delete, clear all, and the app's own addNotification insert).
DROP POLICY IF EXISTS "Parents manage their own notifications"
  ON public.notifications;
CREATE POLICY "Parents manage their own notifications"
  ON public.notifications FOR ALL
  TO authenticated
  USING (parent_id = auth.uid())
  WITH CHECK (parent_id = auth.uid());

-- 4b. Kids may only *raise* a notification, and only for themselves.
--
-- Both kid-side call sites run during an active session, so the
-- child -> parent link is proved through homework_sessions rather
-- than through `children` — kids have a SELECT policy on
-- homework_sessions but deliberately cannot read `children`, and an
-- EXISTS against a table the caller can't read evaluates to false,
-- which would silently block every kid insert.
DROP POLICY IF EXISTS "Kids can raise notifications for their parent"
  ON public.notifications;
CREATE POLICY "Kids can raise notifications for their parent"
  ON public.notifications FOR INSERT
  TO authenticated
  WITH CHECK (
    child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
    AND EXISTS (
      SELECT 1 FROM public.homework_sessions hs
      WHERE hs.child_id = notifications.child_id
        AND hs.parent_id = notifications.parent_id
    )
  );

-- 5. RealtimeService subscribes to INSERTs on this table to drive the
-- unread badge, so it has to be in the publication.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END $$;
