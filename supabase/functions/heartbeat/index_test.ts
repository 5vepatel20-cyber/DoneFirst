// Deno tests for the heartbeat edge function.
//
// Run with:
//   cd supabase/functions/heartbeat
//   deno test --allow-net

import {
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  handleHeartbeat,
  SupabaseAdminLike,
} from './index.ts'

interface UpdateCall {
  table: string
  patch: any
  filters: Array<{ col: string; op: string; val: any }>
  returned: any[] | null
  error: any
}

function makeMock(opts: {
  user?: any
  authError?: unknown
  updateError?: unknown
  updateReturned?: any[] | null
} = {}): {
  client: SupabaseAdminLike
  state: { updates: UpdateCall[] }
} {
  const state = { updates: [] as UpdateCall[] }

  const client: SupabaseAdminLike = {
    from: (table: string) => ({
      update: (patch: any) => {
        const filters: UpdateCall['filters'] = []
        const builder: any = {
          eq: (col: string, val: any) => {
            filters.push({ col, op: 'eq', val })
            return builder
          },
          is: (col: string, val: any) => {
            filters.push({ col, op: 'is', val })
            return builder
          },
          select: (_cols: string) => {
            const update: UpdateCall = {
              table,
              patch,
              filters,
              returned: opts.updateReturned ?? null,
              error: opts.updateError ?? null,
            }
            state.updates.push(update)
            return Promise.resolve({
              data: update.returned,
              error: update.error,
            })
          },
        }
        return builder
      },
    }),
    auth: {
      getUser: async (_token: string) => {
        if (opts.authError) {
          return { data: null, error: opts.authError }
        }
        return {
          data: { user: opts.user ?? null },
          error: opts.user ? null : { message: 'no user' },
        }
      },
    },
  }

  return { client, state }
}

function makeReq(opts: {
  method?: string
  auth?: string | null
} = {}): Request {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  }
  if (opts.auth !== null) {
    headers['Authorization'] = opts.auth ?? 'Bearer test-token'
  }
  return new Request('https://test.local/heartbeat', {
    method: opts.method ?? 'POST',
    headers,
  })
}

Deno.test('OPTIONS returns CORS ok', async () => {
  const { client } = makeMock()
  const res = await handleHeartbeat(makeReq({ method: 'OPTIONS' }), client)
  assertEquals(res.status, 200)
  const text = await res.text()
  assertEquals(text, 'ok')
})

Deno.test('GET returns 405', async () => {
  const { client } = makeMock()
  const res = await handleHeartbeat(makeReq({ method: 'GET' }), client)
  assertEquals(res.status, 405)
})

Deno.test('missing Authorization header returns 401', async () => {
  const { client } = makeMock()
  const res = await handleHeartbeat(makeReq({ auth: null }), client)
  assertEquals(res.status, 401)
  const body = await res.json()
  assertEquals(body.ok, false)
})

Deno.test('invalid token returns 401', async () => {
  const { client } = makeMock({ authError: { message: 'invalid' } })
  const res = await handleHeartbeat(makeReq(), client)
  assertEquals(res.status, 401)
})

Deno.test('user without device_id claim returns 401', async () => {
  const { client } = makeMock({
    user: { id: 'u-1', app_metadata: {} },
  })
  const res = await handleHeartbeat(makeReq(), client)
  assertEquals(res.status, 401)
  const body = await res.json()
  assertEquals(body.error, 'Missing device claim')
})

Deno.test('database error returns 500', async () => {
  const { client } = makeMock({
    user: { id: 'u-1', app_metadata: { device_id: 'd-1' } },
    updateError: { message: 'connection lost' },
  })
  const res = await handleHeartbeat(makeReq(), client)
  assertEquals(res.status, 500)
})

Deno.test('revoked device (empty update result) returns 401', async () => {
  // Supabase returns an empty array when the WHERE clause matches
  // no rows. The kid app should clear its tokens on 401.
  const { client } = makeMock({
    user: { id: 'u-1', app_metadata: { device_id: 'd-revoked' } },
    updateReturned: [],
  })
  const res = await handleHeartbeat(makeReq(), client)
  assertEquals(res.status, 401)
  const body = await res.json()
  assertEquals(body.error, 'Device not active')
})

Deno.test('happy path updates kid_devices.last_seen_at and returns 200',
  async () => {
    const { client, state } = makeMock({
      user: { id: 'u-1', app_metadata: { device_id: 'd-active' } },
      updateReturned: [{ id: 'd-active' }],
    })
    const res = await handleHeartbeat(makeReq(), client)
    assertEquals(res.status, 200)
    const body = await res.json()
    assertEquals(body.ok, true)

    // Verify the WHERE clause filters by id AND revoked_at IS NULL.
    assertEquals(state.updates.length, 1)
    const call = state.updates[0]
    assertEquals(call.table, 'kid_devices')
    assertEquals(call.patch.last_seen_at !== undefined, true,
      'last_seen_at is set')
    assertStringIncludes(
      new Date(call.patch.last_seen_at).toISOString(),
      new Date().toISOString().slice(0, 10),
      'last_seen_at is approximately now',
    )
    const idFilter = call.filters.find((f) => f.col === 'id')
    const revokedFilter = call.filters.find((f) =>
      f.col === 'revoked_at' && f.op === 'is'
    )
    assertEquals(idFilter?.val, 'd-active')
    assertEquals(revokedFilter?.val, null,
      'revoked_at IS NULL is part of the WHERE clause')
  })