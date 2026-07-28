-- Migration 21: backfill proof_submissions.session_id.
--
-- submitProofWithUrls — the only proof-submission path in the app
-- (ProofCaptureScreen, used by both the kid's LockedScreen and the
-- parent's task entry screen) — inserted with task_id but no
-- session_id. migration_19 noticed this and deliberately scoped the
-- kid's RLS through task_id to work around it, but nothing scoped the
-- *parent* side that way:
--
--   * ProofService.getProofsForSession filters .eq('session_id', ...)
--   * the parent's SELECT policy on proof_submissions is session
--     scoped too
--
-- so a NULL session_id made the proof invisible to the parent at the
-- database level. The kid's task flipped to 'submitted' and showed
-- "Checking…", while the parent's lock screen sat on "Waiting for
-- proof… Auto-refreshes every 10s" forever with no Approve button.
-- The session could never be completed by approval — only by the
-- min-lock timer expiring. Verified end-to-end on 2026-07-28: the
-- parent's own JWT returned 200 with an empty array for a proof the
-- kid's JWT could read.
--
-- The insert now stamps session_id from the owning task. This fixes
-- the rows written before that, using the same task -> session link.
--
-- Idempotent: only touches rows that are still NULL, so re-running is
-- a no-op. Read-repair only — no proof is created, deleted, or
-- re-graded, and parent_decision is untouched.

UPDATE proof_submissions ps
SET session_id = ht.session_id
FROM homework_tasks ht
WHERE ps.task_id = ht.id
  AND ps.session_id IS NULL;
