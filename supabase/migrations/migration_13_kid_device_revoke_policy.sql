-- Migration 13: Allow parents to revoke their family's kid devices.
--
-- Migration 11 set up kid_devices with RLS:
--   - SELECT for parents (family-scoped)
--   - INSERT/UPDATE/DELETE only via service_role (Edge Functions)
--
-- That meant the parent app couldn't revoke a device directly — it
-- would need a service-role Edge Function round-trip for what's a
-- one-line UPDATE. Add an UPDATE policy here so the parent's
-- "Revoke" button on KidDevicePairingScreen can write directly.
-- We restrict the allowed columns implicitly by only writing
-- revoked_at from the Dart side; the policy permits the UPDATE
-- but doesn't widen visibility beyond what SELECT already grants.
--
-- Idempotent: safe to re-run.

DROP POLICY IF EXISTS "Parents can revoke family kid devices" ON kid_devices;
CREATE POLICY "Parents can revoke family kid devices"
  ON kid_devices FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM parents p
      WHERE p.family_id = kid_devices.family_id
      AND p.id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM parents p
      WHERE p.family_id = kid_devices.family_id
      AND p.id = auth.uid()
    )
  );

-- Helpful view for the parent's dashboard / pairing screen. Joins
-- kid_devices with the child's display name so the parent can see
-- "Aarav's Pixel" without a second query.
DROP VIEW IF EXISTS kid_devices_with_child;
CREATE VIEW kid_devices_with_child AS
  SELECT
    kd.id,
    kd.family_id,
    kd.child_id,
    c.name AS child_display_name,
    kd.device_name,
    kd.paired_at,
    kd.last_seen_at,
    kd.revoked_at,
    -- Convenience: is the device currently online?
    -- last_seen_at within the last 90s = online. Anything older =
    -- offline. NULL last_seen_at = never seen (just paired or revoked).
    CASE
      WHEN kd.revoked_at IS NOT NULL THEN 'revoked'
      WHEN kd.last_seen_at IS NULL THEN 'unknown'
      WHEN kd.last_seen_at > now() - interval '90 seconds' THEN 'online'
      WHEN kd.last_seen_at > now() - interval '24 hours' THEN 'recent'
      ELSE 'stale'
    END AS status
  FROM kid_devices kd
  LEFT JOIN children c ON c.id = kd.child_id;

-- Status values:
--   'online'  — heartbeat within 90s. UI shows green dot.
--   'recent'  — heartbeat within 24h but not last 90s. UI shows amber.
--   'stale'   — last heartbeat > 24h ago. Probably dead battery or
--               wifi off. UI shows gray.
--   'unknown' — never reported (just paired, or revoked before first
--               heartbeat). UI shows gray.
--   'revoked' — revoked_at set. UI hides from active list or shows
--               strikethrough.
