// delete-account — GDPR Article 17 right-to-erasure.
//
// Security model:
//   - Caller must send a valid Supabase access token. Anonymous
//     calls are rejected.
//   - Service-role key is used here so we can cascade through the
//     family's data and finally delete the auth.users row.
//
// Erasure scope (everything we hold about this parent + their family):
//   - children
//     - homework_sessions
//       - proof_submissions (the URLs are signed URLs; the binaries
//         in the 'proof-photos' bucket must be deleted separately)
//       - homework_tasks
//       - break_requests
//     - recurring_schedules
//   - notifications
//   - lock_presets
//   - parent_invites (invites they sent)
//   - families
//   - mistral_verification_log  (operational; we delete with the account)
//   - parents
//   - auth.users (via supabaseAdmin.auth.deleteUser)
//
// Intentionally RETAINED (with comment):
//   - parental_consent rows: COPPA / GDPR-K require us to be able
//     to prove consent was given. We keep the row but it remains
//     keyed on parent_id which is now invalid — render-friendly
//     for audit but no longer resolveable to a deleted user. If
//     true anonymization is required, a separate scheduled job can
//     rewrite parent_id to NULL after a grace period.
//
//   - proof-photos storage objects: this function deletes the
//     proof_submissions rows but does NOT walk the Storage bucket.
//     See the launch checklist for the orphan-cleanup function.

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return json({ success: false, error: 'Method not allowed' }, 405)
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return json({ success: false, error: 'Unauthorized' }, 401)
  }
  const token = authHeader.replace('Bearer ', '')
  const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
  if (authError || !user) {
    return json({ success: false, error: 'Unauthorized' }, 401)
  }
  const userId = user.id

  try {
    const parent = await supabaseAdmin
      .from('parents')
      .select('family_id')
      .eq('id', userId)
      .maybeSingle()
    const familyId = parent?.family_id as string | null

    if (familyId) {
      const { data: children } = await supabaseAdmin
        .from('children')
        .select('id')
        .eq('family_id', familyId)

      for (const child of children ?? []) {
        const { data: sessions } = await supabaseAdmin
          .from('homework_sessions')
          .select('id')
          .eq('child_id', child.id)
        for (const session of sessions ?? []) {
          // proof_submissions has FK CASCADE to homework_sessions so it
          // would auto-delete if the FK is set up that way, but we
          // delete explicitly to be safe across schema versions.
          await supabaseAdmin
            .from('proof_submissions')
            .delete()
            .eq('session_id', session.id)
          await supabaseAdmin
            .from('homework_tasks')
            .delete()
            .eq('session_id', session.id)
          await supabaseAdmin
            .from('break_requests')
            .delete()
            .eq('session_id', session.id)
        }
        await supabaseAdmin
          .from('homework_sessions')
          .delete()
          .eq('child_id', child.id)
        await supabaseAdmin
          .from('recurring_schedules')
          .delete()
          .eq('child_id', child.id)
      }

      await supabaseAdmin.from('children').delete().eq('family_id', familyId)
      await supabaseAdmin.from('notifications').delete().eq('parent_id', userId)
      await supabaseAdmin.from('lock_presets').delete().eq('parent_id', userId)
      await supabaseAdmin.from('parent_invites').delete().eq('inviter_id', userId)
      await supabaseAdmin.from('families').delete().eq('id', familyId)
    }

    // Operational log: this is NOT personal data per se, just a count
    // of how many Mistral calls were made for this parent. We delete
    // it anyway to honor the principle that nothing persists without
    // a legitimate purpose.
    await supabaseAdmin
      .from('mistral_verification_log')
      .delete()
      .eq('parent_id', userId)

    await supabaseAdmin.from('parents').delete().eq('id', userId)
    await supabaseAdmin.auth.deleteUser(userId)

    return json({ success: true })
  } catch (err) {
    console.error('Delete account error:', err)
    return json({ success: false, error: 'Internal error' }, 500)
  }
})