-- Migration 7 (partial): missing CREATE TABLE statements.
--
-- These two tables are referenced by rls_policies.sql but were never
-- created by schema_migrations.sql. Adding them here so RLS can
-- be applied.

CREATE TABLE IF NOT EXISTS recurring_schedules (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  child_id UUID REFERENCES children(id) ON DELETE CASCADE NOT NULL,
  day_of_week INT NOT NULL DEFAULT 0,
  duration_minutes INT NOT NULL DEFAULT 60,
  approval_mode TEXT NOT NULL DEFAULT 'balanced',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS recurring_schedules_child_id_idx
  ON recurring_schedules (child_id);

CREATE TABLE IF NOT EXISTS parent_invites (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  family_id UUID REFERENCES families(id) ON DELETE CASCADE NOT NULL,
  inviter_id UUID REFERENCES parents(id) ON DELETE CASCADE NOT NULL,
  invitee_email TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS parent_invites_family_id_idx
  ON parent_invites (family_id);

CREATE INDEX IF NOT EXISTS parent_invites_inviter_id_idx
  ON parent_invites (inviter_id);

CREATE INDEX IF NOT EXISTS parent_invites_invitee_email_idx
  ON parent_invites (invitee_email);
