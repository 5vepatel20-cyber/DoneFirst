// Deno tests for the claim-pairing edge function.
//
// Run with:
//   cd supabase/functions/claim-pairing
//   deno test --allow-net
//
// These tests exercise handleClaimPairing with a fake Supabase
// admin client. The real Supabase client is replaced by a hand-
// written mock that returns the canned rows the test wants the
// function to see.
//
// If you change handleClaimPairing's contract (status codes, error
// shapes, etc.), update these tests alongside it.

import {
  assertEquals,
  assertExists,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  handleClaimPairing,
  SupabaseAdminLike,
} from './index.ts'

// ---------- mock client ----------

interface PairingRow {
  code: string
  child_id: string
  family_id: string
  expires_at: string
  claimed_at: string | null
  claimed_by_device?: string
}

interface ChildRow {
  id: string
  name: string
}

/** Builds a mock Supabase admin client that returns canned rows
 * from a pre-populated list of pairings + tracks inserts. */
function makeMock(opts: {
  pairings: PairingRow[]
  children?: ChildRow[]
  deviceInsertError?: unknown
  claimError?: unknown
  createUserError?: unknown
  signInError?: unknown
  userId?: string
} = { pairings: [] }): {
  client: SupabaseAdminLike
  state: {
    insertedDevices: any[]
    claimUpdates: any[]
    createdUser: any
    signInCalled: boolean
    childLookups: string[]
  }
} {
  const state = {
    insertedDevices: [] as any[],
    claimUpdates: [] as any[],
    createdUser: null as any,
    signInCalled: false,
    childLookups: [] as string[],
  }

  // Tiny query builder that mimics the chained PostgREST API:
  //   .from('x').select(...).eq('code', c).maybeSingle()
  //   .from('x').insert({...}).select('id').single()
  //   .from('x').update({...}).eq('code', c).is('claimed_at', null)
  function table(name: string): any {
    if (name === 'device_pairings') {
      return {
        select: () => ({
          eq: (_col: string, val: string) => ({
            maybeSingle: async () => {
              const found = opts.pairings.find((p) => p.code === val)
              return { data: found ?? null, error: null }
            },
          }),
        }),
        update: (patch: any) => ({
          eq: (_col: string, _val: string) => ({
            is: (_col2: string, _val2: any) => {
              state.claimUpdates.push(patch)
              if (opts.claimError) {
                return Promise.resolve({ error: opts.claimError })
              }
              return Promise.resolve({ error: null })
            },
          }),
        }),
      }
    }
    if (name === 'kid_devices') {
      return {
        insert: (row: any) => {
          state.insertedDevices.push(row)
          if (opts.deviceInsertError) {
            return Promise.resolve({
              data: null,
              error: opts.deviceInsertError,
            })
          }
          const deviceId = opts.userId ?? 'device-test-id'
          return Promise.resolve({
            data: { id: deviceId },
            error: null,
          }).then((r) => ({
            select: () => ({
              single: async () => r,
            }),
          }))
        },
      }
    }
    if (name === 'children') {
      return {
        select: (_cols: string) => ({
          eq: (_col: string, val: string) => ({
            maybeSingle: async () => {
              state.childLookups.push(val)
              const childList = opts.children ?? []
              const found = childList.find((c) => c.id === val)
              return { data: found ?? null, error: null }
            },
          }),
        }),
      }
    }
    throw new Error(`mock: unhandled table ${name}`)
  }

  const client: SupabaseAdminLike = {
    from: table,
    auth: {
      admin: {
        createUser: async (input: any) => {
          if (opts.createUserError) {
            return { data: null, error: opts.createUserError }
          }
          state.createdUser = input
          return {
            data: { user: { id: 'kid-user-id' } },
            error: null,
          }
        },
      },
      signInWithPassword: async (input: any) => {
        state.signInCalled = true
        if (opts.signInError) {
          return { data: null, error: opts.signInError }
        }
        return {
          data: {
            session: {
              access_token: 'mock-access',
              refresh_token: 'mock-refresh',
            },
          },
          error: null,
        }
      },
    },
  }

  return { client, state }
}

// ---------- helpers ----------

function makeReq(body: unknown, method = 'POST'): Request {
  return new Request('https://test.local/claim-pairing', {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  })
}

// ---------- tests ----------

Deno.test('OPTIONS request returns CORS ok', async () => {
  const { client } = makeMock()
  const res = await handleClaimPairing(makeReq(null, 'OPTIONS'), client)
  assertEquals(res.status, 200)
  const text = await res.text()
  assertEquals(text, 'ok')
})

Deno.test('non-POST method returns 405', async () => {
  const { client } = makeMock()
  const res = await handleClaimPairing(makeReq(null, 'GET'), client)
  assertEquals(res.status, 405)
  const body = await res.json()
  assertEquals(body.success, false)
})

Deno.test('malformed JSON body returns 400', async () => {
  const { client } = makeMock()
  const res = await handleClaimPairing(makeReq('not json'), client)
  assertEquals(res.status, 400)
  const body = await res.json()
  assertEquals(body.success, false)
  assertEquals(body.error, 'Invalid JSON body')
})

Deno.test('empty code returns 400 BAD_CODE', async () => {
  const { client } = makeMock()
  const res = await handleClaimPairing(makeReq({ code: '' }), client)
  assertEquals(res.status, 400)
  const body = await res.json()
  assertEquals(body.success, false)
  assertEquals(body.error, 'Code must be 6 digits')
})

Deno.test('non-numeric code returns 400 BAD_CODE', async () => {
  const { client } = makeMock()
  const res = await handleClaimPairing(makeReq({ code: 'abc123' }), client)
  assertEquals(res.status, 400)
})

Deno.test('5-digit code returns 400 BAD_CODE', async () => {
  const { client } = makeMock()
  const res = await handleClaimPairing(makeReq({ code: '12345' }), client)
  assertEquals(res.status, 400)
})

Deno.test('7-digit code returns 400 BAD_CODE', async () => {
  const { client } = makeMock()
  const res = await handleClaimPairing(makeReq({ code: '1234567' }), client)
  assertEquals(res.status, 400)
})

Deno.test('code with whitespace is trimmed before validation', async () => {
  const { client } = makeMock()
  const res = await handleClaimPairing(makeReq({ code: '  123456  ' }), client)
  // After trim it's a valid 6-digit number — proceeds to lookup,
  // which returns no match → 410. Verifies the trim is applied.
  assertEquals(res.status, 410)
})

Deno.test('unknown code returns 410 (does not leak existence)', async () => {
  const { client } = makeMock({ pairings: [] })
  const res = await handleClaimPairing(makeReq({ code: '111111' }), client)
  assertEquals(res.status, 410)
  const body = await res.json()
  assertEquals(body.success, false)
  assertEquals(body.error, 'Invalid or expired code')
})

Deno.test('already-claimed code returns 410', async () => {
  const { client } = makeMock({
    pairings: [{
      code: '222222',
      child_id: 'c1',
      family_id: 'f1',
      expires_at: new Date(Date.now() + 60_000).toISOString(),
      claimed_at: new Date().toISOString(),
    }],
  })
  const res = await handleClaimPairing(makeReq({ code: '222222' }), client)
  assertEquals(res.status, 410)
})

Deno.test('expired code returns 410', async () => {
  const { client } = makeMock({
    pairings: [{
      code: '333333',
      child_id: 'c1',
      family_id: 'f1',
      expires_at: new Date(Date.now() - 60_000).toISOString(),
      claimed_at: null,
    }],
  })
  const res = await handleClaimPairing(makeReq({ code: '333333' }), client)
  assertEquals(res.status, 410)
})

Deno.test('kid_devices insert failure returns 500', async () => {
  const { client } = makeMock({
    pairings: [{
      code: '444444',
      child_id: 'c1',
      family_id: 'f1',
      expires_at: new Date(Date.now() + 60_000).toISOString(),
      claimed_at: null,
    }],
    deviceInsertError: { message: 'disk full' },
  })
  const res = await handleClaimPairing(makeReq({ code: '444444' }), client)
  assertEquals(res.status, 500)
})

Deno.test('createUser failure returns 500', async () => {
  const { client } = makeMock({
    pairings: [{
      code: '555555',
      child_id: 'c1',
      family_id: 'f1',
      expires_at: new Date(Date.now() + 60_000).toISOString(),
      claimed_at: null,
    }],
    createUserError: { message: 'rate limit' },
  })
  const res = await handleClaimPairing(makeReq({ code: '555555' }), client)
  assertEquals(res.status, 500)
})

Deno.test('signInWithPassword failure returns 500', async () => {
  const { client } = makeMock({
    pairings: [{
      code: '666666',
      child_id: 'c1',
      family_id: 'f1',
      expires_at: new Date(Date.now() + 60_000).toISOString(),
      claimed_at: null,
    }],
    signInError: { message: 'invalid creds' },
  })
  const res = await handleClaimPairing(makeReq({ code: '666666' }), client)
  assertEquals(res.status, 500)
})

Deno.test('happy path returns 200 with session tokens', async () => {
  const { client, state } = makeMock({
    pairings: [{
      code: '777777',
      child_id: 'c-happy',
      family_id: 'f-happy',
      expires_at: new Date(Date.now() + 60_000).toISOString(),
      claimed_at: null,
    }],
    children: [{ id: 'c-happy', name: 'Aarav' }],
  })
  const res = await handleClaimPairing(
    makeReq({ code: '777777', device_name: 'Sam phone' }),
    client,
  )
  assertEquals(res.status, 200)
  const body = await res.json()
  assertEquals(body.success, true)
  assertEquals(body.access_token, 'mock-access')
  assertEquals(body.refresh_token, 'mock-refresh')
  assertEquals(body.child_id, 'c-happy')
  assertEquals(body.family_id, 'f-happy')
  assertEquals(body.child_name, 'Aarav')
  assertExists(body.device_id)
  assertStringIncludes(body.device_id, 'device-test-id')

  // The children lookup should have been called for the paired
  // child's id, so the kid lock screen can greet the kid by name.
  assertEquals(state.childLookups.length, 1)
  assertEquals(state.childLookups[0], 'c-happy')

  // The inserted device row should carry the parent-claimed
  // child_id/family_id and the device_name we sent.
  assertEquals(state.insertedDevices.length, 1)
  assertEquals(state.insertedDevices[0].child_id, 'c-happy')
  assertEquals(state.insertedDevices[0].family_id, 'f-happy')
  assertEquals(state.insertedDevices[0].device_name, 'Sam phone')

  // createUser's app_metadata should carry the kid_device marker
  // and the same child/family/device ids.
  assertEquals(state.createdUser.app_metadata.kid_device, true)
  assertEquals(state.createdUser.app_metadata.child_id, 'c-happy')
  assertEquals(state.createdUser.app_metadata.device_id, body.device_id)

  // The mint user is unique per device — the email is derived
  // from the device UUID + a synthetic TLD.
  assertStringIncludes(state.createdUser.email, '@donefirst.invalid')

  // signInWithPassword was called with the same credentials used
  // for createUser (so the signIn actually succeeds).
  assertEquals(state.signInCalled, true)
})

Deno.test('happy path returns child_name=null when children row missing', async () => {
  // Pairing references a child id that has no corresponding row in
  // the children mock. The kid still gets a working session, but
  // child_name falls back to null so the lock screen can show its
  // generic "there" greeting rather than failing the whole pair.
  const { client } = makeMock({
    pairings: [{
      code: '787878',
      child_id: 'c-orphan',
      family_id: 'f-orphan',
      expires_at: new Date(Date.now() + 60_000).toISOString(),
      claimed_at: null,
    }],
    children: [],
  })
  const res = await handleClaimPairing(
    makeReq({ code: '787878' }),
    client,
  )
  assertEquals(res.status, 200)
  const body = await res.json()
  assertEquals(body.success, true)
  assertEquals(body.child_id, 'c-orphan')
  assertEquals(body.child_name, null)
})

Deno.test('happy path with whitespace-only device_name stores null',
  async () => {
    const { client, state } = makeMock({
      pairings: [{
        code: '888888',
        child_id: 'c1',
        family_id: 'f1',
        expires_at: new Date(Date.now() + 60_000).toISOString(),
        claimed_at: null,
      }],
    })
    const res = await handleClaimPairing(
      makeReq({ code: '888888', device_name: '   ' }),
      client,
    )
    assertEquals(res.status, 200)
    assertEquals(state.insertedDevices[0].device_name, null,
      'whitespace-only device_name is coerced to null before insert')
  })