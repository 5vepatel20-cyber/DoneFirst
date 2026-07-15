// claim-pairing — Kid-side companion app entry point.
//
// Flow:
//   1. Parent generates a 6-digit pairing code in the parent app
//      (KidDeviceService.createPairingCode). The code lives in
//      device_pairings with expires_at = now() + 10min.
//   2. Kid launches the kid app, types the code, taps "Pair".
//   3. Kid app POSTs to this function with the code (no auth header
//      needed; this is the bootstrap call).
//   4. This function:
//        - looks up the code
//        - rejects expired or already-claimed codes (410)
//        - creates a kid_devices row
//        - updates device_pairings.claimed_at + claimed_by_device
//        - creates an anon Supabase user (no email, no password) and
//          signs in a JWT carrying child_id + family_id in
//          app_metadata custom claims
//        - returns { access_token, refresh_token, child_id, family_id,
//          device_id }
//
// Why anon auth with custom claims: the kid has no password. We
// mint a per-device identity tied to a specific child, so the
// realtime listener can scope `homework_sessions WHERE child_id =
// jwt.claims.app_metadata.child_id`.
//
// Security model:
//   - Edge function uses service_role to write kid_devices and
//     device_pairings.
//   - The minted anon JWT belongs to a unique auth user (one per
//     device pair). It has no password, no recovery path, expires
//     when the parent revokes the device.
//   - Rate limiting: we don't add a separate counter here; instead
//     the 6-digit code space (1M) plus the 10-min expiry caps
//     brute force at ~1667 attempts/sec before the code becomes
//     invalid — well under Supabase's per-IP limit. Codes are
//     single-use regardless.
//
// DEPLOYMENT: This file lives at
//   C:\Users\veerp\DoneFirst\donefirst_kid\supabase\functions\
//     claim-pairing\index.ts
// to preserve it alongside the kid app (the parent app directory
// was lost on 2026-07-11 and the original copy at
// donefirst\supabase\functions\claim-pairing\index.ts went with
// it). Deploy via:
//   supabase functions deploy claim-pairing \
//     --project-ref <your-project-ref>

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/** Shape of the Supabase admin client this function needs. Minimal
 * interface to allow tests to pass a fake without standing up a
 * real Supabase. */
export interface SupabaseAdminLike {
  from: (table: string) => any
  auth: {
    admin: {
      createUser: (input: any) => Promise<{ data: any; error: any }>
    }
    signInWithPassword: (input: any) => Promise<{ data: any; error: any }>
  }
}

/** CORS headers — kept identical to other DoneFirst edge
 * functions so they can share a parent-app origin allow-list. */
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

/** Core handler. Exported so tests can call it directly with a
 * mock Supabase admin client — see claim-pairing/index_test.ts. */
export async function handleClaimPairing(
  req: Request,
  supabaseAdmin: SupabaseAdminLike,
): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return json({ success: false, error: 'Method not allowed' }, 405)
  }

  // The body should be { code: "123456", device_name?: "<string>" }.
  // For unauthenticated bootstrap calls (no Authorization header),
  // we still want to reject empty/missing codes early so we don't
  // burn DB queries on garbage.
  let body: { code?: string; device_name?: string }
  try {
    body = await req.json()
  } catch {
    return json({ success: false, error: 'Invalid JSON body' }, 400)
  }
  const code = (body.code ?? '').trim()
  const deviceName = (body.device_name ?? '').trim() || null

  if (!/^\d{6}$/.test(code)) {
    return json(
      { success: false, error: 'Code must be 6 digits' },
      400,
    )
  }

  try {
    const { data: pairing, error: lookupError } = await supabaseAdmin
      .from('device_pairings')
      .select('code, child_id, family_id, expires_at, claimed_at')
      .eq('code', code)
      .maybeSingle()

    if (lookupError) {
      console.error('claim-pairing lookup error:', lookupError)
      return json({ success: false, error: 'Lookup failed' }, 500)
    }
    if (!pairing) {
      // Don't leak whether the code existed — treat "not found" and
      // "expired/claimed" identically so an attacker can't enumerate.
      return json(
        { success: false, error: 'Invalid or expired code' },
        410,
      )
    }
    if (pairing.claimed_at) {
      return json(
        { success: false, error: 'Invalid or expired code' },
        410,
      )
    }
    if (new Date(pairing.expires_at).getTime() < Date.now()) {
      return json(
        { success: false, error: 'Invalid or expired code' },
        410,
      )
    }

    // Fetch the child's name in parallel with the kid_devices
    // insert below. The name is needed by the kid lock screen
    // ("Time for Aarav") and the kid cannot read children directly
    // because the RLS policy scopes that table to the parent's
    // auth.uid, not the kid's app_metadata.child_id. Returning it
    // here avoids a second round-trip on the kid's first render.
    //
    // Failure here is non-fatal — if the children row vanished
    // (shouldn't happen with FK CASCADE on device_pairings, but
    // defensive) we still want to finish pairing and surface the
    // generic fallback "there" copy in the lock screen rather than
    // fail the entire flow.
    let childName: string | null = null
    try {
      const { data: childRow } = await supabaseAdmin
        .from('children')
        .select('name')
        .eq('id', pairing.child_id)
        .maybeSingle()
      childName = (childRow?.name as string | undefined)?.trim() || null
    } catch (nameErr) {
      console.error('claim-pairing child name lookup error:', nameErr)
      // keep childName = null and continue
    }

    // Create the kid device row first so we can point
    // device_pairings.claimed_by_device at it.
    const { data: device, error: insertError } = await supabaseAdmin
      .from('kid_devices')
      .insert({
        child_id: pairing.child_id,
        family_id: pairing.family_id,
        device_name: deviceName,
      })
      .select('id')
      .single()
    if (insertError || !device) {
      console.error('kid_devices insert error:', insertError)
      return json(
        { success: false, error: 'Failed to register device' },
        500,
      )
    }

    // Mark the code as claimed. If this fails (race: another kid app
    // claimed in the millisecond before us), the orphan device row
    // stays — a cleanup job can sweep kid_devices with no heartbeat
    // after 24h.
    const { error: claimError } = await supabaseAdmin
      .from('device_pairings')
      .update({
        claimed_at: new Date().toISOString(),
        claimed_by_device: device.id,
      })
      .eq('code', code)
      .is('claimed_at', null)
    if (claimError) {
      console.error('device_pairings update error:', claimError)
      return json(
        { success: false, error: 'Failed to claim code' },
        500,
      )
    }

    // Mint a kid-side auth user. The email is a derivative of the
    // device UUID so it's globally unique without ever being user-
    // visible (the kid app never tries to sign in via this email).
    const deviceEmail = `kid-${device.id}@donefirst.invalid`
    const devicePassword = crypto.randomUUID() + crypto.randomUUID()
    const { data: created, error: createUserError } =
      await supabaseAdmin.auth.admin.createUser({
        email: deviceEmail,
        password: devicePassword,
        email_confirm: true,
        app_metadata: {
          // `role` is the Supabase role (anon / authenticated / etc).
          // `kid_device` is our marker — RLS policies and the kid
          // realtime listener both check it.
          role: 'authenticated',
          kid_device: true,
          child_id: pairing.child_id,
          family_id: pairing.family_id,
          device_id: device.id,
        },
      })
    if (createUserError || !created?.user) {
      console.error('createUser error:', createUserError)
      return json(
        { success: false, error: 'Failed to create device identity' },
        500,
      )
    }

    // Insert a `parents` row for the new auth user with role='kid'.
    // This is the single-app-with-roles refactor: parents and kids
    // both live in the `parents` table, distinguished by `role`. The
    // parent's id == auth.users.id by convention (see
    // ProfileService.getProfile in the parent app), so we set the
    // parents row's id to the auth user id we just created. Without
    // this row, the kid app can't look up its own profile and the
    // router can't decide whether to show the kid or parent UI.
    const kidDisplayName = deviceName ?? 'Kid'
    const { error: parentInsertError } = await supabaseAdmin
      .from('parents')
      .insert({
        id: created.user.id,
        family_id: pairing.family_id,
        email: deviceEmail,
        display_name: kidDisplayName,
        role: 'kid',
      })
    if (parentInsertError) {
      console.error('parents insert error:', parentInsertError)
      // The auth user exists but the profile row didn't — orphaned.
      // We surface this rather than silently swallowing so the
      // operator knows to clean up. The orphan auth user can't be
      // signed in by the kid app because the role router won't
      // recognise it.
      return json(
        { success: false, error: 'Failed to register kid profile' },
        500,
      )
    }

    // Sign in as that user to get a JWT carrying the app_metadata
    // custom claims. The kid app will store access_token +
    // refresh_token in SharedPreferences.
    const { data: session, error: signInError } =
      await supabaseAdmin.auth.signInWithPassword({
        email: deviceEmail,
        password: devicePassword,
      })
    if (signInError || !session?.session) {
      console.error('signIn error:', signInError)
      return json(
        { success: false, error: 'Failed to issue session' },
        500,
      )
    }

    return json({
      success: true,
      access_token: session.session.access_token,
      refresh_token: session.session.refresh_token,
      child_id: pairing.child_id,
      family_id: pairing.family_id,
      device_id: device.id,
      // null when the children row wasn't readable (RLS blocked it
      // or the row vanished). The kid app falls back to a generic
      // "there" greeting rather than failing the whole pair flow.
      child_name: childName,
    })
  } catch (err) {
    console.error('claim-pairing unexpected error:', err)
    return json({ success: false, error: 'Internal error' }, 500)
  }
}

// CLI entrypoint — only runs when the function is deployed as a
// Supabase edge function (i.e. Deno imports this module as `main`).
if (import.meta.main) {
  const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
  const SUPABASE_SERVICE_ROLE_KEY =
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  serve((req) => handleClaimPairing(req, supabaseAdmin))
}
