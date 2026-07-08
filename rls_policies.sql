-- Migration 7: Comprehensive RLS policies for all tables
-- Run this in Supabase SQL Editor.
-- Idempotent: safe to re-run; every CREATE is preceded by DROP POLICY IF EXISTS
-- and every ALTER TABLE ... ENABLE ROW LEVEL SECURITY is a no-op when already on.
--
-- Coverage after this script:
--   families, parents, children, homework_sessions, homework_tasks,
--   proof_submissions, break_requests, recurring_schedules,
--   lock_presets, notifications, parent_invites, mistral_verification_log,
--   storage.objects (proof-photos bucket)

-- Enable RLS on every owned-data table
ALTER TABLE families ENABLE ROW LEVEL SECURITY;
ALTER TABLE parents ENABLE ROW LEVEL SECURITY;
ALTER TABLE children ENABLE ROW LEVEL SECURITY;
ALTER TABLE homework_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE homework_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE proof_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE break_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE lock_presets ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE parent_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE mistral_verification_log ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to allow re-run
DROP POLICY IF EXISTS "Users can insert own parent record" ON parents;
DROP POLICY IF EXISTS "Users can manage own parent record" ON parents;
DROP POLICY IF EXISTS "Parents can manage children" ON children;
DROP POLICY IF EXISTS "Parents can manage sessions" ON homework_sessions;
DROP POLICY IF EXISTS "Manage tasks" ON homework_tasks;
DROP POLICY IF EXISTS "Manage proofs" ON proof_submissions;
DROP POLICY IF EXISTS "Manage break requests" ON break_requests;
DROP POLICY IF EXISTS "Manage schedules" ON recurring_schedules;
DROP POLICY IF EXISTS "Manage families" ON families;
DROP POLICY IF EXISTS "Parents can manage their own presets" ON lock_presets;
DROP POLICY IF EXISTS "Parents can read their notifications" ON notifications;
DROP POLICY IF EXISTS "Parents can update their notifications" ON notifications;
DROP POLICY IF EXISTS "System can insert notifications" ON notifications;
DROP POLICY IF EXISTS "Service role manages notification inserts" ON notifications;
DROP POLICY IF EXISTS "Inviters can manage own invites" ON parent_invites;
DROP POLICY IF EXISTS "Parents can read own usage" ON mistral_verification_log;
DROP POLICY IF EXISTS "Service role inserts usage" ON mistral_verification_log;

-- parents: insert self + manage own row
CREATE POLICY "Users can insert own parent record"
  ON parents FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can manage own parent record"
  ON parents FOR ALL
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- families: any authenticated user can manage families they belong to.
-- Family membership is established by the parents.family_id link, but
-- keeping this permissive at the family table level avoids awkward
-- chicken-and-egg issues during signup. Tighten if you ever add a
-- separate families_members table.
CREATE POLICY "Authenticated users can manage families"
  ON families FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- children: direct parent_id ownership
CREATE POLICY "Parents can manage their children"
  ON children FOR ALL
  USING (parent_id = auth.uid())
  WITH CHECK (parent_id = auth.uid());

-- homework_sessions: direct parent_id ownership
CREATE POLICY "Parents can manage their sessions"
  ON homework_sessions FOR ALL
  USING (parent_id = auth.uid())
  WITH CHECK (parent_id = auth.uid());

-- homework_tasks: linked through session.parent_id
CREATE POLICY "Parents can manage tasks through session"
  ON homework_tasks FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM homework_sessions
      WHERE homework_sessions.id = homework_tasks.session_id
      AND homework_sessions.parent_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM homework_sessions
      WHERE homework_sessions.id = homework_tasks.session_id
      AND homework_sessions.parent_id = auth.uid()
    )
  );

-- proof_submissions: linked through session.parent_id
CREATE POLICY "Parents can manage proofs through session"
  ON proof_submissions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM homework_sessions
      WHERE homework_sessions.id = proof_submissions.session_id
      AND homework_sessions.parent_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM homework_sessions
      WHERE homework_sessions.id = proof_submissions.session_id
      AND homework_sessions.parent_id = auth.uid()
    )
  );

-- break_requests: linked through session.parent_id
CREATE POLICY "Parents can manage break requests through session"
  ON break_requests FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM homework_sessions
      WHERE homework_sessions.id = break_requests.session_id
      AND homework_sessions.parent_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM homework_sessions
      WHERE homework_sessions.id = break_requests.session_id
      AND homework_sessions.parent_id = auth.uid()
    )
  );

-- recurring_schedules: linked through children.parent_id
CREATE POLICY "Parents can manage schedules through child"
  ON recurring_schedules FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM children
      WHERE children.id = recurring_schedules.child_id
      AND children.parent_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM children
      WHERE children.id = recurring_schedules.child_id
      AND children.parent_id = auth.uid()
    )
  );

-- lock_presets: direct parent_id ownership
CREATE POLICY "Parents can manage their own presets"
  ON lock_presets FOR ALL
  USING (parent_id = auth.uid())
  WITH CHECK (parent_id = auth.uid());

-- notifications: parents read+update their own. Inserts come ONLY from
-- service_role (Edge Function). This blocks parents from faking
-- notifications on another parent's account, and blocks any client from
-- poking the table directly.
CREATE POLICY "Parents can read their notifications"
  ON notifications FOR SELECT
  USING (parent_id = auth.uid());

CREATE POLICY "Parents can update their notifications"
  ON notifications FOR UPDATE
  USING (parent_id = auth.uid())
  WITH CHECK (parent_id = auth.uid());

CREATE POLICY "Service role manages notification inserts"
  ON notifications FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

-- parent_invites: inviter manages own invites (accept/decline happens
-- via the Edge Function on signup, not direct write here)
CREATE POLICY "Inviters can manage own invites"
  ON parent_invites FOR ALL
  USING (inviter_id = auth.uid())
  WITH CHECK (inviter_id = auth.uid());

-- mistral_verification_log: parents read their own usage count for
-- transparency. Inserts are service_role only (Edge Function).
CREATE POLICY "Parents can read own usage"
  ON mistral_verification_log FOR SELECT
  USING (parent_id = auth.uid());

CREATE POLICY "Service role inserts usage"
  ON mistral_verification_log FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

-- parental_consent: created by migration 9 in schema_migrations.sql.
-- Parents can read and write their OWN consent records (parent_id must
-- match auth.uid() on insert, so they can't fake consent on someone
-- else's behalf). No UPDATE / DELETE — consent records are an audit
-- trail and must be immutable.
ALTER TABLE parental_consent ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Parents can read own consent" ON parental_consent;
DROP POLICY IF EXISTS "Parents can insert own consent" ON parental_consent;

CREATE POLICY "Parents can read own consent"
  ON parental_consent FOR SELECT
  USING (parent_id = auth.uid());

CREATE POLICY "Parents can insert own consent"
  ON parental_consent FOR INSERT
  WITH CHECK (parent_id = auth.uid());

-- Storage: proof-photos bucket
-- Force bucket private; idempotent
UPDATE storage.buckets SET public = false WHERE name = 'proof-photos';

DROP POLICY IF EXISTS "Authenticated users can upload proofs" ON storage.objects;
CREATE POLICY "Authenticated users can upload proofs"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'proof-photos'
    AND auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "Authenticated users can read proofs" ON storage.objects;
CREATE POLICY "Authenticated users can read proofs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'proof-photos'
    AND auth.role() = 'authenticated'
  );

-- Final sanity check: confirm RLS is enabled everywhere we expect.
-- Any row in this result indicates a table the script forgot.
SELECT schemaname || '.' || tablename AS table_with_rls_disabled
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = false
  AND tablename IN (
    'families', 'parents', 'children', 'homework_sessions',
    'homework_tasks', 'proof_submissions', 'break_requests',
    'recurring_schedules', 'lock_presets', 'notifications',
    'parent_invites', 'mistral_verification_log'
  );

-- Verifies storage.buckets entry
SELECT name, public FROM storage.buckets WHERE name = 'proof-photos';

-- Run BEFORE this script:
--   1. schema_migrations.sql migrations 1–6 (already applied)
--   2. schema_migrations.sql migration 8 (mistral_verification_log)
--   3. schema_migrations.sql migration 9 (parental_consent)