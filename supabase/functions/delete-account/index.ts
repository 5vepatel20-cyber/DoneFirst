import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response('Unauthorized', { status: 401 })
  }

  const token = authHeader.replace('Bearer ', '')
  const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
  if (authError || !user) {
    return new Response('Unauthorized', { status: 401 })
  }

  const userId = user.id

  try {
    const parent = await supabaseAdmin.from('parents').select('family_id').eq('id', userId).maybeSingle()
    const familyId = parent?.family_id as string | null

    if (familyId) {
      const { data: children } = await supabaseAdmin.from('children').select('id').eq('family_id', familyId)
      for (const child of children ?? []) {
        const { data: sessions } = await supabaseAdmin.from('homework_sessions').select('id').eq('child_id', child.id)
        for (const session of sessions ?? []) {
          await supabaseAdmin.from('proof_submissions').delete().eq('session_id', session.id)
          await supabaseAdmin.from('homework_tasks').delete().eq('session_id', session.id)
          await supabaseAdmin.from('break_requests').delete().eq('session_id', session.id)
        }
        await supabaseAdmin.from('homework_sessions').delete().eq('child_id', child.id)
        await supabaseAdmin.from('recurring_schedules').delete().eq('child_id', child.id)
      }
      await supabaseAdmin.from('children').delete().eq('family_id', familyId)
      await supabaseAdmin.from('notifications').delete().eq('parent_id', userId)
      await supabaseAdmin.from('lock_presets').delete().eq('parent_id', userId)
      await supabaseAdmin.from('parent_invites').delete().eq('inviter_id', userId)
      await supabaseAdmin.from('families').delete().eq('id', familyId)
    }

    await supabaseAdmin.from('parents').delete().eq('id', userId)
    await supabaseAdmin.auth.deleteUser(userId)

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Delete account error:', err)
    return new Response(JSON.stringify({ success: false, error: 'Internal error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
