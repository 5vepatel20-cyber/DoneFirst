-- Migration 1: Subject tags for homework tasks
ALTER TABLE homework_tasks ADD COLUMN IF NOT EXISTS subject TEXT DEFAULT 'General';

-- Migration 2: Parent notes on proof approval
ALTER TABLE proof_submissions ADD COLUMN IF NOT EXISTS parent_note TEXT;

-- Migration 3: Lock configuration presets
CREATE TABLE IF NOT EXISTS lock_presets (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  parent_id UUID REFERENCES parents(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  min_lock_minutes INT NOT NULL DEFAULT 60,
  max_lift_minutes INT NOT NULL DEFAULT 120,
  approval_mode TEXT NOT NULL DEFAULT 'balanced',
  selected_packs TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Migration 4: In-app notifications
CREATE TABLE IF NOT EXISTS notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  parent_id UUID REFERENCES parents(id) ON DELETE CASCADE NOT NULL,
  child_id UUID REFERENCES children(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable row-level security
ALTER TABLE lock_presets ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- RLS policies for lock_presets
CREATE POLICY "Parents can manage their own presets"
  ON lock_presets FOR ALL
  USING (parent_id = auth.uid())
  WITH CHECK (parent_id = auth.uid());

-- RLS policies for notifications
CREATE POLICY "Parents can read their notifications"
  ON notifications FOR SELECT
  USING (parent_id = auth.uid());

CREATE POLICY "System can insert notifications"
  ON notifications FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Parents can update their notifications"
  ON notifications FOR UPDATE
  USING (parent_id = auth.uid());

-- Migration 5: Multiple images per proof
ALTER TABLE proof_submissions ADD COLUMN IF NOT EXISTS image_urls TEXT[] DEFAULT '{}';

-- Migration 6: Streak tracking
ALTER TABLE children ADD COLUMN IF NOT EXISTS streak_count INT DEFAULT 0;
ALTER TABLE children ADD COLUMN IF NOT EXISTS last_streak_date DATE;

-- Migration 8: Mistral verification usage log
-- Created alongside rls_policies.sql (migration 7). One row per
-- successful verify-proof call; used by the Edge Function for the
-- daily-cap check and (in future) by parents to see their usage.
CREATE TABLE IF NOT EXISTS mistral_verification_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  parent_id UUID REFERENCES parents(id) ON DELETE CASCADE NOT NULL,
  called_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS mistral_verification_log_parent_called_at_idx
  ON mistral_verification_log (parent_id, called_at DESC);

-- Migration 9: Parental consent audit log
-- COPPA / GDPR-K require verifiable parental consent before collecting
-- personal data from children. This table is the audit trail.
--
-- Inserts go through the client (with parent_id = auth.uid() enforced
-- by RLS), so they can never be back-dated by a malicious actor
-- pretending to be someone else. The current policy version is
-- captured at insert time, so future policy updates can require
-- re-consent.
CREATE TABLE IF NOT EXISTS parental_consent (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  parent_id UUID REFERENCES parents(id) ON DELETE CASCADE NOT NULL,
  consent_type TEXT NOT NULL,
  consent_version TEXT NOT NULL,
  policy_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS parental_consent_parent_id_idx
  ON parental_consent (parent_id, created_at DESC);

-- Migration 9b: richer parental-consent audit data
-- The original migration 9 table has only the bare minimum
-- (consent_type + consent_version). For a defensible COPPA audit
-- trail we also capture:
--   - signed_name: the parent's typed full name, which many jurisdictions
--     (US E-SIGN, EU eIDAS) accept as a valid e-signature when paired
--     with the rest of the consent record
--   - acknowledgments: a JSONB map of {key: bool} for each individual
--     item the parent agreed to, so we can show exactly what they
--     agreed to at this policy version (not just "they agreed to v1")
--   - child_name: optional, set when the consent was captured during
--     child-add rather than at signup
ALTER TABLE parental_consent
  ADD COLUMN IF NOT EXISTS signed_name TEXT,
  ADD COLUMN IF NOT EXISTS acknowledgments JSONB,
  ADD COLUMN IF NOT EXISTS child_name TEXT;
