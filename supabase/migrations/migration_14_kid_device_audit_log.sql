-- Migration 14: kid_device_events audit log.
--
-- Goal: when a parent generates a pairing code, when a kid claims
-- it, when a parent cancels an unused code, and when a parent
-- revokes a paired device, we want a single searchable timeline
-- for the family. Today the only way to know "did Aarav's iPad
-- get revoked yesterday?" is to grep cloud logs — a parent
-- shouldn't need to do that.
--
-- The events are produced by Postgres triggers instead of being
-- inserted from the Dart side. Trigger-based emission is more
-- robust: any future code path that touches device_pairings or
-- kid_devices (a new edge function, a SQL fixup, a manual psql
-- session during an outage) automatically lights up the log
-- without the author having to remember to insert an event row.
--
-- Idempotent: safe to re-run.

CREATE TABLE IF NOT EXISTS kid_device_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  child_id uuid REFERENCES children(id) ON DELETE SET NULL,
  kid_device_id uuid REFERENCES kid_devices(id) ON DELETE SET NULL,
  -- The code itself, captured at insert time. We don't FK to
  -- device_pairings because that row is deleted on cancel/claim
  -- and the event should outlive it.
  device_pairing_code text,
  event_type text NOT NULL CHECK (event_type IN (
    'code_generated',
    'code_claimed',
    'code_cancelled',
    'device_revoked'
  )),
  created_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb
);

-- Family-scoped timeline reads. The composite index covers the
-- only query path we have right now (latest events for a family)
-- — extra indexes can wait until we add filters by child/device.
CREATE INDEX IF NOT EXISTS kid_device_events_family_created_idx
  ON kid_device_events(family_id, created_at DESC);

ALTER TABLE kid_device_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Parents see family kid device events" ON kid_device_events;
CREATE POLICY "Parents see family kid device events"
  ON kid_device_events FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM parents p
      WHERE p.family_id = kid_device_events.family_id
      AND p.id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- Trigger: code_generated
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION emit_kid_device_event_code_generated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO kid_device_events
    (family_id, child_id, device_pairing_code, event_type)
  VALUES
    (NEW.family_id, NEW.child_id, NEW.code, 'code_generated');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_code_generated ON device_pairings;
CREATE TRIGGER trg_code_generated
  AFTER INSERT ON device_pairings
  FOR EACH ROW
  EXECUTE FUNCTION emit_kid_device_event_code_generated();

-- ---------------------------------------------------------------------------
-- Trigger: code_claimed
-- Fires when claimed_at transitions from NULL to non-NULL. We
-- ignore UPDATE writes that touch claimed_at without setting it
-- so we don't double-count claim + later edits.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION emit_kid_device_event_code_claimed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF OLD.claimed_at IS NULL AND NEW.claimed_at IS NOT NULL THEN
    INSERT INTO kid_device_events
      (family_id, child_id, device_pairing_code, event_type, kid_device_id)
    VALUES
      (NEW.family_id, NEW.child_id, NEW.code, 'code_claimed', NEW.claimed_by_device);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_code_claimed ON device_pairings;
CREATE TRIGGER trg_code_claimed
  AFTER UPDATE ON device_pairings
  FOR EACH ROW
  EXECUTE FUNCTION emit_kid_device_event_code_claimed();

-- ---------------------------------------------------------------------------
-- Trigger: code_cancelled
-- Fires AFTER DELETE. We only log a cancel event if the row was
-- unclaimed; a claimed row being deleted by cleanup should NOT
-- count as a cancel, because the device record already emits a
-- 'code_claimed' event for it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION emit_kid_device_event_code_cancelled()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF OLD.claimed_at IS NULL THEN
    INSERT INTO kid_device_events
      (family_id, child_id, device_pairing_code, event_type)
    VALUES
      (OLD.family_id, OLD.child_id, OLD.code, 'code_cancelled');
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_code_cancelled ON device_pairings;
CREATE TRIGGER trg_code_cancelled
  AFTER DELETE ON device_pairings
  FOR EACH ROW
  EXECUTE FUNCTION emit_kid_device_event_code_cancelled();

-- ---------------------------------------------------------------------------
-- Trigger: device_revoked
-- Fires when revoked_at transitions from NULL to non-NULL. The
-- UPDATE policy added in migration_13 lets parents do this from
-- the Dart side; the trigger keeps the audit log in sync.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION emit_kid_device_event_device_revoked()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL THEN
    INSERT INTO kid_device_events
      (family_id, child_id, kid_device_id, event_type)
    VALUES
      (NEW.family_id, NEW.child_id, NEW.id, 'device_revoked');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_device_revoked ON kid_devices;
CREATE TRIGGER trg_device_revoked
  AFTER UPDATE ON kid_devices
  FOR EACH ROW
  EXECUTE FUNCTION emit_kid_device_event_device_revoked();

-- ---------------------------------------------------------------------------
-- View: kid_device_events_with_context
-- Joins events with children + devices so the parent app can show
-- "Aarav's Pixel 8 revoked 2h ago" without N+1 queries.
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS kid_device_events_with_context;
CREATE VIEW kid_device_events_with_context AS
  SELECT
    e.id,
    e.family_id,
    e.event_type,
    e.created_at,
    e.device_pairing_code,
    e.metadata,
    e.child_id,
    c.name AS child_name,
    e.kid_device_id,
    kd.device_name AS device_name
  FROM kid_device_events e
  LEFT JOIN children c ON c.id = e.child_id
  LEFT JOIN kid_devices kd ON kd.id = e.kid_device_id;

-- ---------------------------------------------------------------------------
-- Realtime: let the parent app receive live event notifications.
-- Without this the dashboard would need to poll. ADD is idempotent
-- in PostgreSQL — re-adding an already-included table is a no-op.
-- ---------------------------------------------------------------------------
ALTER PUBLICATION supabase_realtime ADD TABLE kid_device_events;
