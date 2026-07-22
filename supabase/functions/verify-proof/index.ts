// verify-proof — Mistral AI verification proxy.
//
// Security model:
//   - The MISTRAL_API_KEY is held here as an env var, never in the client.
//   - Callers must send a valid Supabase access token (the same one they
//     use for app API calls). Anonymous calls are rejected.
//   - Daily call limit per user (MISTRAL_DAILY_LIMIT env var, default 50)
//     protects against quota theft and runaway client bugs.
//
// Verdict quality (see issue "AI approves random pictures"):
//   - The prompt is strict: it enumerates what does and does NOT count as
//     homework and forces a low confidence when the image is ambiguous.
//   - A server-side confidence floor (MISTRAL_CONFIDENCE_FLOOR, default
//     0.7) downgrades a low-confidence "approved" to "needs_review" so a
//     hesitant model can never silently green-light a random photo. The
//     floor lives here (not the client) so every caller gets the same
//     policy and it can be tuned without shipping an app build.
//
// Storage:
//   - Each successful call inserts one row into mistral_verification_log
//     so parents can see their usage in-app and so the daily cap is
//     enforceable across function restarts.
//
// Failure modes:
//   - 401 if no/invalid token
//   - 429 if over the daily limit
//   - 200 with { decision: "needs_review", reason: "..." } on any internal
//     error, so the kid's UI doesn't crash mid-session.

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const MISTRAL_API_URL = 'https://api.mistral.ai/v1/chat/completions'
const MISTRAL_API_KEY = Deno.env.get('MISTRAL_API_KEY')
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const DAILY_LIMIT = Number(Deno.env.get('MISTRAL_DAILY_LIMIT') ?? '50')
// Below this confidence, an "approved" verdict is downgraded to
// "needs_review" so a hesitant model can't silently pass a random photo.
// Clamped to [0,1]; a malformed env value falls back to 0.7.
const CONFIDENCE_FLOOR = (() => {
  const raw = Number(Deno.env.get('MISTRAL_CONFIDENCE_FLOOR') ?? '0.7')
  if (!Number.isFinite(raw)) return 0.7
  return Math.min(1, Math.max(0, raw))
})()

// Strict verification prompt. The old prompt ("if it looks like valid
// homework, approve") skewed the model toward approving anything; this
// one enumerates accept/reject cases and demands a high bar + honest
// confidence, which the server-side floor below then enforces.
const SYSTEM_PROMPT = [
  'You are a strict homework-proof verifier for a parental-control app.',
  'A parent will only trust you if you REJECT photos that are not real homework.',
  '',
  'APPROVE (decision "approved") only when the image clearly shows schoolwork:',
  'a worksheet, workbook, textbook page, handwritten notes/answers, a math',
  'problem set, an essay, or a computer/tablet screen showing schoolwork.',
  'There must be legible academic content, not just "a book exists".',
  '',
  'REJECT (decision "rejected") when the image is clearly NOT homework:',
  'selfies or people, pets, toys, games, TV/video, food, random rooms or',
  'objects, memes, screenshots of apps/chats, blank/black photos, or a',
  'finger over the lens.',
  '',
  'Use "needs_review" ONLY when you genuinely cannot tell (too blurry,',
  'too dark, cropped, or partially schoolwork).',
  '',
  'Be honest about "confidence" (0.0-1.0): it is how sure you are of the',
  'decision. If you are guessing, confidence MUST be below 0.5.',
  '',
  'Respond in this JSON format ONLY:',
  '{"decision": "approved|needs_review|rejected", "confidence": 0.0-1.0, "reason": "brief explanation"}',
].join('\n')

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders,
      ...extra,
    },
  })
}

async function authenticate(req: Request): Promise<string | null> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return null
  const token = authHeader.replace('Bearer ', '')
  const { data, error } = await supabaseAdmin.auth.getUser(token)
  if (error || !data?.user) return null
  return data.user.id
}

async function countDailyCalls(parentId: string): Promise<number> {
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
  const { count, error } = await supabaseAdmin
    .from('mistral_verification_log')
    .select('*', { count: 'exact', head: true })
    .eq('parent_id', parentId)
    .gte('called_at', since)
  if (error) {
    // Fail open: if the log table is missing, log a server error and let
    // the request through. Better to over-verify than to break kids mid-session.
    console.error('countDailyCalls error:', error)
    return 0
  }
  return count ?? 0
}

async function logCall(parentId: string) {
  const { error } = await supabaseAdmin
    .from('mistral_verification_log')
    .insert({ parent_id: parentId })
  if (error) console.error('logCall error:', error)
}

// Normalize + enforce the confidence floor. A low-confidence "approved"
// becomes "needs_review" (never a silent pass); the reason records why so
// it shows up in the parent UI and the app/edge logs.
function applyPolicy(
  raw: { decision?: string; confidence?: number; reason?: string },
): { decision: string; confidence: number; reason: string } {
  let decision = raw.decision ?? 'needs_review'
  const confidence =
    typeof raw.confidence === 'number' && Number.isFinite(raw.confidence)
      ? Math.min(1, Math.max(0, raw.confidence))
      : 0
  let reason = raw.reason ?? ''
  if (decision === 'approved' && confidence < CONFIDENCE_FLOOR) {
    decision = 'needs_review'
    reason =
      `Low confidence (${confidence.toFixed(2)} < ${CONFIDENCE_FLOOR}); ` +
      `needs a human look. ${reason}`.trim()
  }
  return { decision, confidence, reason }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return json({ decision: 'needs_review', reason: 'Method not allowed' }, 405)
  }
  if (!MISTRAL_API_KEY) {
    return json({
      decision: 'needs_review',
      confidence: 0,
      reason: 'Server misconfigured (missing API key)',
    })
  }

  // Auth — refuse anonymous calls
  const userId = await authenticate(req)
  if (!userId) {
    return json({ decision: 'needs_review', reason: 'Unauthorized' }, 401)
  }

  // Daily cap — protect quota from being drained by a single account
  const callsToday = await countDailyCalls(userId)
  if (callsToday >= DAILY_LIMIT) {
    return json({
      decision: 'needs_review',
      reason: `Daily verification limit reached (${DAILY_LIMIT}). Try again tomorrow.`,
    }, 429)
  }

  let body: { imageUrl?: string }
  try {
    body = await req.json()
  } catch {
    return json({ decision: 'needs_review', reason: 'Invalid JSON body' }, 400)
  }
  const imageUrl = body.imageUrl
  if (!imageUrl || typeof imageUrl !== 'string') {
    return json({ decision: 'needs_review', reason: 'Missing imageUrl' }, 400)
  }

  // Only accept image URLs that point at our own Supabase Storage.
  // Without this check, a client could pass any public URL (e.g. a
  // huge image hosted elsewhere) and burn the parent's daily Mistral
  // quota + cost on it.
  //
  // Storage URLs come in two flavours:
  //   - Public bucket:  https://<project>.supabase.co/storage/v1/object/public/<bucket>/<path>
  //   - Signed URL:     https://<project>.supabase.co/storage/v1/object/sign/<bucket>/<path>?...
  //
  // proof-photos is a private bucket, so only the signed form is valid
  // for it, but we accept both for forward-compatibility in case a
  // future bucket becomes public.
  const supabaseUrl = new URL(SUPABASE_URL)
  const allowedPrefixes = [
    `${supabaseUrl.origin}/storage/v1/object/sign/`,
    `${supabaseUrl.origin}/storage/v1/object/public/`,
  ]
  if (!allowedPrefixes.some((p) => imageUrl.startsWith(p))) {
    return json({
      decision: 'needs_review',
      reason: 'imageUrl must be a Supabase Storage URL',
    }, 400)
  }

  // Call Mistral
  let mistralBody: unknown
  try {
    const mistralRes = await fetch(MISTRAL_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${MISTRAL_API_KEY}`,
      },
      body: JSON.stringify({
        model: 'mistral-small-latest',
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: SYSTEM_PROMPT,
              },
              {
                type: 'image_url',
                image_url: imageUrl,
              },
            ],
          },
        ],
        response_format: { type: 'json_object' },
        // Low temperature — we want a consistent, calibrated verdict,
        // not a creative one.
        temperature: 0.1,
        max_tokens: 256,
      }),
    })

    if (!mistralRes.ok) {
      const errText = await mistralRes.text()
      console.error('Mistral API error:', mistralRes.status, errText)
      return json({
        decision: 'needs_review',
        confidence: 0,
        reason: `Mistral error: ${mistralRes.status}`,
      })
    }

    mistralBody = await mistralRes.json()
  } catch (err) {
    console.error('Mistral fetch error:', err)
    return json({
      decision: 'needs_review',
      confidence: 0,
      reason: 'Verification service unavailable',
    })
  }

  // Log successful call AFTER successful Mistral response so we don't
  // count failed calls against the daily quota
  await logCall(userId)

  const content = (mistralBody as any)?.choices?.[0]?.message?.content ?? '{}'
  let resultJson: { decision?: string; confidence?: number; reason?: string }
  try {
    resultJson = JSON.parse(content)
  } catch {
    return json({
      decision: 'needs_review',
      confidence: 0,
      reason: 'Could not parse verifier response',
    })
  }

  const result = applyPolicy(resultJson)
  // Observability: log the raw model verdict and the enforced result so
  // we can see, per call, exactly what the model said vs. what we
  // returned (surfaces "why did this random photo pass?" instantly).
  console.log(
    'verify-proof verdict',
    JSON.stringify({
      user: userId,
      raw: resultJson,
      enforced: result,
      floor: CONFIDENCE_FLOOR,
    }),
  )
  return json(result)
})
