-- Migration 19: kid-side write policies for the paired-device app.
--
-- The kid app (lib/screens/kid/*) runs under a kid JWT whose identity
-- lives in auth.jwt() -> 'app_metadata' ->> 'child_id'. Several kid
-- screens read AND write rows, but the only policies on these tables
-- were parent-scoped (parent_id = auth.uid()), so every kid write
-- failed with RLS 42501 and every kid read returned zero rows.
--
-- Tables covered:
--   * break_requests  — kid "Ask for a break" (INSERT). SELECT already
--                       granted by migration 15.
--   * homework_tasks  — kid LockedScreen task list: getTasks (SELECT),
--                       addTask (INSERT), status='submitted' (UPDATE),
--                       swipe-to-delete (DELETE).
--   * proof_submissions — kid submits proof via ProofCaptureScreen
--                       (INSERT) + AI verify write (UPDATE ai_* cols) +
--                       read (SELECT) + delete-with-task (DELETE).
--
-- All kid scoping keys off the child_id JWT claim, mirroring
-- migration_17's "Kid can read own sessions". Parents keep their
-- existing FOR ALL policies untouched.
--
-- Idempotent: every policy is DROP ... IF EXISTS then CREATE.
--
-- Helper expression used throughout:
--   the signed-in kid's child_id =
--     (auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid


-- ===============================================================
-- break_requests — kid may request a break for their own session.
-- (Fixes "Ask for a break" → 42501.) SELECT already exists (mig 15);
-- parent FOR ALL still governs approve/deny/update.
-- ===============================================================
DROP POLICY IF EXISTS "Kids can request their own session breaks" ON break_requests;
CREATE POLICY "Kids can request their own session breaks"
  ON break_requests FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM homework_sessions hs
      WHERE hs.id = break_requests.session_id
      AND hs.child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
    )
  );


-- ===============================================================
-- homework_tasks — kid may manage tasks for their own session.
-- Scoped via the task's session -> child_id. A single FOR ALL policy
-- is safe here: the kid legitimately reads, adds, submits and deletes
-- tasks on their own active session, and nothing on this table is
-- parent-only.
-- ===============================================================
DROP POLICY IF EXISTS "Kids manage tasks in their own session" ON homework_tasks;
CREATE POLICY "Kids manage tasks in their own session"
  ON homework_tasks FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM homework_sessions hs
      WHERE hs.id = homework_tasks.session_id
      AND hs.child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM homework_sessions hs
      WHERE hs.id = homework_tasks.session_id
      AND hs.child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
    )
  );


-- ===============================================================
-- proof_submissions — kid may submit / read / delete proofs for their
-- own tasks, and write the AI verification result. But the kid must
-- NOT be able to grade their own proof, so parent_decision is capped
-- to 'pending' (or NULL) on any kid write. Grading stays parent-only
-- via the existing parent FOR ALL policy.
--
-- Scope is via task_id -> homework_tasks -> homework_sessions.child_id
-- (NOT session_id): submitProofWithUrls inserts with only task_id set,
-- leaving session_id NULL, so a session_id-based policy would reject
-- the kid's own legitimate insert.
-- ===============================================================
-- SELECT
DROP POLICY IF EXISTS "Kids read proofs for their own tasks" ON proof_submissions;
CREATE POLICY "Kids read proofs for their own tasks"
  ON proof_submissions FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM homework_tasks ht
      JOIN homework_sessions hs ON hs.id = ht.session_id
      WHERE ht.id = proof_submissions.task_id
      AND hs.child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
    )
  );

-- INSERT — kid submits a proof; may not pre-grade it.
DROP POLICY IF EXISTS "Kids submit proofs for their own tasks" ON proof_submissions;
CREATE POLICY "Kids submit proofs for their own tasks"
  ON proof_submissions FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM homework_tasks ht
      JOIN homework_sessions hs ON hs.id = ht.session_id
      WHERE ht.id = proof_submissions.task_id
      AND hs.child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
    )
    AND (proof_submissions.parent_decision IS NULL
         OR proof_submissions.parent_decision = 'pending')
  );

-- UPDATE — kid writes the AI verification result after submit; the
-- row must remain ungraded (parent_decision stays pending/NULL) so a
-- kid can't self-approve by crafting an UPDATE.
DROP POLICY IF EXISTS "Kids update ungraded proofs for their own tasks" ON proof_submissions;
CREATE POLICY "Kids update ungraded proofs for their own tasks"
  ON proof_submissions FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM homework_tasks ht
      JOIN homework_sessions hs ON hs.id = ht.session_id
      WHERE ht.id = proof_submissions.task_id
      AND hs.child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM homework_tasks ht
      JOIN homework_sessions hs ON hs.id = ht.session_id
      WHERE ht.id = proof_submissions.task_id
      AND hs.child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
    )
    AND (proof_submissions.parent_decision IS NULL
         OR proof_submissions.parent_decision = 'pending')
  );

-- DELETE — kid removes a proof when deleting its task.
DROP POLICY IF EXISTS "Kids delete proofs for their own tasks" ON proof_submissions;
CREATE POLICY "Kids delete proofs for their own tasks"
  ON proof_submissions FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM homework_tasks ht
      JOIN homework_sessions hs ON hs.id = ht.session_id
      WHERE ht.id = proof_submissions.task_id
      AND hs.child_id = ((auth.jwt() -> 'app_metadata' ->> 'child_id')::uuid)
    )
  );
