-- Fix: parent DELETE on proof_submissions was broken because
-- proof_submissions.session_id is NULL in practice, so the old
-- policy's qual (session_id → homework_sessions.parent_id) always
-- failed. Replace with a chain through homework_tasks →
-- homework_sessions so the parent can delete proofs for their
-- children's tasks.

DROP POLICY IF EXISTS "Parents delete proofs for their children"
  ON proof_submissions;
DROP POLICY IF EXISTS "Parents delete proofs via homework_tasks"
  ON proof_submissions;

CREATE POLICY "Parents delete proofs via homework_tasks"
ON proof_submissions
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM homework_tasks ht
    JOIN homework_sessions hs ON hs.id = ht.session_id
    WHERE ht.id = proof_submissions.task_id
      AND hs.parent_id = auth.uid()
  )
);
