-- Migration 7: Comprehensive RLS policies for all tables
-- Run this in Supabase SQL Editor

-- Enable RLS on all tables
ALTER TABLE families ENABLE ROW LEVEL SECURITY;
ALTER TABLE parents ENABLE ROW LEVEL SECURITY;
ALTER TABLE children ENABLE ROW LEVEL SECURITY;
ALTER TABLE homework_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE homework_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE proof_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE break_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_schedules ENABLE ROW LEVEL SECURITY;

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

-- parents
CREATE POLICY "Users can insert own parent record"
  ON parents FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can manage own parent record"
  ON parents FOR ALL
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- families
CREATE POLICY "Authenticated users can manage families"
  ON families FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- children
CREATE POLICY "Parents can manage their children"
  ON children FOR ALL
  USING (parent_id = auth.uid())
  WITH CHECK (parent_id = auth.uid());

-- homework_sessions
CREATE POLICY "Parents can manage their sessions"
  ON homework_sessions FOR ALL
  USING (parent_id = auth.uid())
  WITH CHECK (parent_id = auth.uid());

-- homework_tasks (linked through session's parent_id)
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

-- proof_submissions (linked through session via task or directly)
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

-- break_requests (linked through session)
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

-- recurring_schedules (linked through child's parent_id)
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

-- Storage: proof-photos bucket
-- Bucket-level RLS
UPDATE storage.buckets SET public = false WHERE name = 'proof-photos';

-- Allow authenticated uploads to proof-photos
CREATE POLICY "Authenticated users can upload proofs"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'proof-photos'
    AND auth.role() = 'authenticated'
  );

-- Allow authenticated reads of proofs
CREATE POLICY "Authenticated users can read proofs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'proof-photos'
    AND auth.role() = 'authenticated'
  );
