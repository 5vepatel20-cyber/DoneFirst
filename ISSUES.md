# DoneFirst — Known Issues & Bugs

Last updated: 2026-07-19

---

## Critical — Blocking core flow

### 1. Kid pairing does not work end-to-end on web

**Status:** Partially fixed, needs verification

**Symptoms:**
- Parent generates a pairing code → kid enters code → "Could not pair" error
- OR kid app won't open at all after pairing attempt (error message shown)

**Root causes found and fixed:**

| # | Bug | Fix | Status |
|---|-----|-----|--------|
| 1a | **CORS preflight failure** — Edge Functions (`claim-pairing`, `verify-proof`, `delete-account`, `heartbeat`) had `Access-Control-Allow-Headers: authorization, content-type` but the Supabase Flutter SDK sends an `apikey` header on every request. Browser rejected the preflight. | Added `apikey` to `Access-Control-Allow-Headers` in all 4 Edge Functions and redeployed. | Fixed & deployed |
| 1b | **`recoverSession()` called with wrong argument** — `kid_auth_service.dart` called `_supabase.auth.recoverSession(access)` passing a raw JWT string. But `recoverSession(String)` expects a full Session JSON object (`{"access_token":"...","refresh_token":"...","user":{...}}`). `json.decode()` on a JWT always throws, so `currentSession` was never set and `isPaired` was always false. | Replaced with `_supabase.auth.setSession(refresh, accessToken: access)` which correctly takes the refresh token + access token, decodes the JWT locally, and calls `GET /auth/v1/user` to hydrate the session. | Fixed & deployed |
| 1c | **PairingScreen used separate KidAuthService instance** — `PairingScreen` created its own `KidAuthService()`, separate from KidRoot's global `kidAuth`. After pairing, `_childId` was set on the local instance but `kidAuth._childId` stayed null. | Pass global `kidAuth` to `PairingScreen` via required constructor parameter. | Fixed & committed |
| 1d | **`restoreSession` cleared tokens on network errors** — Any error from `recoverSession` (including transient network failures) triggered `_clearTokens()`, forcing re-pairing on every launch. | New error handling distinguishes auth errors (clear tokens) from network errors (keep tokens). Also falls back to local JWT payload decoding when `setSession` network call fails. | Fixed & committed |

**Current state:** Code fixes are committed and web build is deployed. Needs end-to-end testing in browser.

**Test steps:**
1. Open http://localhost:8080
2. Sign up / login as parent
3. Go to Devices → Pair → generate a 6-digit code
4. Open incognito window → enter the code
5. Kid should transition from PairingScreen to WaitingScreen/UnlockedScreen
6. Refresh the browser → kid should auto-restore session (not see PairingScreen again)

---

### 2. `setSession` on web may fail due to CORS or network issues

**Status:** Mitigated but not fully resolved

**Problem:** `setSession(refresh, accessToken:)` calls `GET /auth/v1/user` to verify the token and hydrate the user object. On web, this is a cross-origin request to `https://<project>.supabase.co/auth/v1/user`. If this fails (CORS, network timeout), `currentSession` is never set.

**Mitigation applied:**
- 8-second timeout on all `setSession` calls
- Fallback to local JWT payload decoding (base64url) to extract `app_metadata` claims without a network call
- `isPaired` checks both `currentSession != null` AND `_childId != null`

**Still needed:** Verify that Supabase's built-in auth API has proper CORS headers for the `apikey` header. May need to configure in Supabase Dashboard → Settings → API → CORS origins.

---

### 3. Mistral API key exposed in repo

**Status:** Not fixed

**Problem:** The Mistral API key `Ppm5qdhZ8A5XQPrOm7GtbDXoR9CxNbOv` was committed to the working tree in an earlier session and was visible in `DEVELOPER_HANDOFF.md` and build artifacts.

**Action required:** Rotate the key at https://console.mistral.ai/ and update `MISTRAL_API_KEY` env var in Supabase Dashboard → Edge Functions → verify-proof → Environment Variables.

---

## High — Affecting functionality

### 4. Missing `migration_11` file in repo

**Status:** Fixed

**Problem:** The original `migration_11_device_pairings_and_kid_devices.sql` was lost when the parent app directory was deleted on 2026-07-11. The tables (`device_pairings`, `kid_devices`) existed on the live DB but had no corresponding migration file in the repo.

**Fix:** Reconstructed the migration from live DB inspection on 2026-07-19 and added to `supabase/migrations/`. Includes a note that it should not be applied to databases that already have these objects.

---

### 5. Duplicate RLS policies on `device_pairings`

**Status:** Cosmetic, not harmful

**Problem:** The live `device_pairings` table has 4 RLS policies: 3 fine-grained policies from the original migration 11, plus an `ALL` policy added manually during this session. The `ALL` policy is a superset of the other 3, so the duplicates are harmless but messy.

**Action:** Clean up by dropping the 3 redundant fine-grained policies, keeping only the `ALL` policy. Low priority.

---

### 6. `schema_migrations.sql` policies need `DROP POLICY IF EXISTS`

**Status:** Fixed

**Problem:** Running `schema_migrations.sql` on a live DB that already had some policies caused `CREATE POLICY` to fail with "policy already exists" errors.

**Fix:** Added `DROP POLICY IF EXISTS` before each `CREATE POLICY` in `schema_migrations.sql`.

---

## Medium — Needed before launch

### 7. "Confirm email" must be disabled in Supabase Auth settings

**Status:** User confirmed done

**Problem:** Supabase's default auth setting requires email confirmation. The Edge Function creates kid auth users with `email_confirm: true` to bypass this, but parent sign-ups would be blocked if "Confirm email" is enabled.

**Action:** Supabase Dashboard → Authentication → Providers → Email → uncheck "Confirm email".

---

### 8. Android release keystore not generated

**Status:** Not started

**Action:** Generate a release keystore with:
```bash
keytool -genkey -v -keystore ~/donefirst-upload.jks -alias donefirst -keyalg RSA -keysize 2048 -validity 10000
```
Then copy `android/key.properties.example` → `android/key.properties` and fill in credentials.

---

### 9. Real app blocking requires native platform work

**Status:** Not started

**iOS:** Requires Apple Developer Program enrollment ($99/yr) + `com.apple.developer.family-controls` entitlement (2+ week review). Then implement `FamilyControls` + `ManagedSettings` in Swift.

**Android:** Requires `AccessibilityService` + `UsageStats` permission. User must manually enable AccessibilityService in Settings.

**Estimated timeline:** 4-7 weeks of native development, gated on Apple enrollment.

---

### 10. Legal review needed

**Status:** Not started

**Action:** Send `PRIVACY.md` and `TERMS.md` to a lawyer for review before app store submission.

---

## Low — Polish / nice-to-have

### 11. `MISTRAL_DAILY_LIMIT` env var not set

**Problem:** Defaults to 50. Can be set in Supabase Dashboard if a custom limit is desired.

---

### 12. `kid_device_events` audit log table — triggers need testing

**Problem:** Migration 14 creates `kid_device_events` table with triggers on `device_pairings` and `kid_devices`. Triggers were applied to the live DB but not tested with real data.

---

### 13. `parent_invites` table uses `invitee_email` not `invitee_id`

**Problem:** The RLS policy for `parent_invites` in `rls_policies.sql` referenced `invitee_id` but the actual column is `invitee_email`. This was fixed when applying the policy manually, but the `rls_policies.sql` file in the repo may still have the wrong column name.

---

### 14. Web session persistence race condition

**Problem:** On web, `initSupabase()` calls `SupabaseAuth.recoverSession()` internally, which reads from Supabase's internal browser localStorage. If a kid session was stored there by a previous `setSession()` call, the SDK recovers it. Then `EntryPoint._resolveRoute()` sees the kid user and routes to `/kid` — which might be correct, but could also cause the parent dashboard to be inaccessible if the parent logs out and the kid session persists in Supabase's internal storage.

**Action:** Add explicit sign-out of Supabase session when navigating between parent/kid modes.

---

## Test results (2026-07-19)

| Test | Result |
|------|--------|
| `flutter build web` | Pass (159s) |
| `flutter test` (185+ tests) | All pass |
| Edge Function `claim-pairing` via curl | Pass (HTTP 200, tokens returned) |
| Live DB audit (device_pairings, kid_devices, RLS) | All tables/policies present |
| `schema_migrations.sql` applied | Pass |
| `rls_policies.sql` applied | Pass |
| End-to-end pairing in browser | **Needs verification** |
| Cold launch session restore in browser | **Needs verification** |
