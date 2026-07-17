-- Migration 16: break_ends_at for crash-resilient kid-side expiry.
--
-- Goal: today the parent app's BreakTimer is purely local. If the
-- parent kills the app, the device runs out of battery, or the
-- network drops mid-break, no one ever writes ended_at to the
-- break_requests row — and the kid app, which only releases the
-- lock when it sees an end-of-break realtime event, stays
-- unlocked indefinitely.
--
-- This migration adds a `break_ends_at` column the parent stamps
-- at approve time so the kid-side can self-expire without waiting
-- for the parent's endBreak write.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, partial index guarded.
--
-- Roll forward: parent BreakService.approveBreak stamps
--   break_ends_at = now() + 5 min (matches the BreakTimer default).
--   Kid RealtimeService reads break_ends_at on every realtime
--   event + on the bootstrap read; if started_at + 5 min has
--   passed in local wall time, it re-engages the lock locally
--   even if no completed/cancelled event has arrived.

ALTER TABLE break_requests
  ADD COLUMN IF NOT EXISTS break_ends_at TIMESTAMPTZ;

-- Partial index — most rows are completed/cancelled with a NULL
-- break_ends_at, so we only index "currently approved" rows. Lets
-- the kid's bootstrap read "is there a live break for me?" hit a
-- tiny index instead of seq-scanning break_requests.
CREATE INDEX IF NOT EXISTS break_requests_active_idx
  ON break_requests (session_id, break_ends_at)
  WHERE break_ends_at IS NOT NULL;
