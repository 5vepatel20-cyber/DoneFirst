import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'

const MISTRAL_API_URL = 'https://api.mistral.ai/v1/chat/completions'
const MISTRAL_API_KEY = Deno.env.get('MISTRAL_API_KEY')

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  if (!MISTRAL_API_KEY) {
    return new Response(
      JSON.stringify({ decision: 'needs_review', confidence: 0, reason: 'Server misconfigured' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  }

  try {
    const { imageUrl } = await req.json()

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
                text: 'You are verifying homework proof photos. Analyze the image and decide if it shows legitimate homework (worksheet, written answers, textbook, notes, computer screen with schoolwork). If it looks like valid homework, respond with decision "approved". If unclear or suspicious, respond with "needs_review". If clearly not homework, respond with "rejected". Respond in this JSON format ONLY: {"decision": "approved|needs_review|rejected", "confidence": 0.0-1.0, "reason": "brief explanation"}',
              },
              {
                type: 'image_url',
                image_url: imageUrl,
              },
            ],
          },
        ],
        response_format: { type: 'json_object' },
        max_tokens: 256,
      }),
    })

    if (!mistralRes.ok) {
      const errText = await mistralRes.text()
      console.error('Mistral API error:', mistralRes.status, errText)
      return new Response(
        JSON.stringify({ decision: 'needs_review', confidence: 0, reason: `Mistral error: ${mistralRes.status}` }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )
    }

    const mistralBody = await mistralRes.json()
    const content = mistralBody.choices?.[0]?.message?.content ?? '{}'
    const resultJson = JSON.parse(content)

    return new Response(JSON.stringify(resultJson), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Edge function error:', err)
    return new Response(
      JSON.stringify({ decision: 'needs_review', confidence: 0, reason: 'Internal error' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  }
})
