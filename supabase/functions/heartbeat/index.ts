// heartbeat — Kid-side app liveness signal.
//
// Called every 30 seconds by the kid app once it has a session
// (post-claim-pairing). Increments kid_devices.last_seen_at for
// the device, which the parent app reads to compute the green /
// gray / red status dot.
//
// Auth model:
//   - Caller sends their kid-app access_token (a real Supabase JWT).
//   - We resolve device_id from the JWT's app_metadata.kid_device
//     claim. The kid app never tells us which device it claims to
//     be — the JWT is the source of truth.
//   - If the device_id claim is missing or the row doesn't exist
//     (parent revoked it), respond 401 so the kid app flips to the
//     "Reconnecting" state and stops enforcing.
//
// What we don't do:
//   - No cron-side auto-offline. The parent UI computes
//     (now - last_seen_at > 90s) inline so there's no scheduled
//     job to maintain.
//
// DEPLOYMENT: This file lives at
//   C:\Users\veerp\DoneFirst\donefirst_kid\supabase\functions\
//     heartbeat\index.ts
// to preserve it alongside the kid app (the parent app directory
// was lost on 2026-07-11). Deploy via:
//   supabase functions deploy heartbeat \
//     --project-ref <your-project-ref>

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/** Minimal Supabase admin shape this function needs. Exported so
 * tests can pass a fake without a real Supabase. */
export interface SupabaseAdminLike {
  from: (table: string) => any
  auth: {
    getUser: (token: string) => Promise<{ data: any; error: any }>
  }
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return Response.json
    ? Response.json(body, {
        status,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      })
    : new Response(JSON.stringify(body), {
        status,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      })
}

/** Core handler. Exported for tests. */
export async function handleHeartbeat(
  req: Request,
  supabaseAdmin: SupabaseAdminLike,
): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return json({ ok: false, error: 'Method not allowed' }, 405)
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return json({ ok: false, error: 'Unauthorized' }, 401)
  }
  const token = authHeader.replace('Bearer ', '')
  const { data: { user }, error: authError } =
    await supabaseAdmin.auth.getUser(token)
  if (authError || !user) {
    return json({ ok: false, error: 'Unauthorized' }, 401)
  }

  // Supabase exposes app_metadata under user.app_metadata; with our
  // claim-pairing flow it carries { kid_device: true, device_id, ... }.
  const deviceId = (user.app_metadata as Record<string, unknown>)?.device_id as
    | string
    | undefined
  if (!deviceId) {
    return json({ ok: false, error: 'Missing device claim' }, 401)
  }

  try {
    // Single UPDATE — only flips last_seen_at on a still-active row.
    // A revoked device (revoked_at NOT NULL) updates successfully on
    // the parent-side check, but we additionally guard against
    // calling heartbeat on a row the parent already deleted.
    const { data, error } = await supabaseAdmin
      .from('kid_devices')
      .update({ last_seen_at: new Date().toISOString() })
      .eq('id', deviceId)
      .is('revoked_at', null)
      .select('id')

    if (error) {
      console.error('heartbeat update error:', error)
      return json({ ok: false, error: 'Database error' }, 500)
    }
    if (!data || data.length === 0) {
      // Device was revoked between claim and now. Kid app should
      // clear its tokens and flip back to the pairing screen.
      return json({ ok: false, error: 'Device not active' }, 401)
    }
    return json({ ok: true })
  } catch (err) {
    console.error('heartbeat unexpected error:', err)
    return json({ ok: false, error: 'Internal error' }, 500)
  }
}

// CLI entrypoint — only runs when deployed to Supabase.
if (import.meta.main) {
  const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
  const SUPABASE_SERVICE_ROLE_KEY =
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  serve((req) => handleHeartbeat(req, supabaseAdmin))
}
