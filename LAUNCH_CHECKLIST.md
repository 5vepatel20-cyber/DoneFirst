# DoneFirst — Launch Checklist

This is the single source of truth for what needs to happen before
DoneFirst is shippable to the public app stores. Everything in this
document requires action by the human owner — `claude` cannot do it
from this environment.

Status legend: ✅ done · ⚠️ done in code, needs infra apply · ❌ not done

---

## 1. Security & privacy

| # | Action | Status | Where |
|---|---|---|---|
| 1.1 | Run `rls_policies.sql` against the live Supabase project | ⚠️ | Supabase Dashboard → SQL Editor → New query → paste file → Run |
| 1.2 | Run `schema_migrations.sql` migration 8 — creates `mistral_verification_log` table | ❌ | Supabase SQL Editor (file in repo) |
| 1.2b | Run `schema_migrations.sql` migration 9 — creates `parental_consent` audit table | ❌ | Supabase SQL Editor |
| 1.3 | Verify `proof-photos` bucket is private after running 1.1 (file ends with a SELECT that should return `public = false`) | ⚠️ | Should match the query in `rls_policies.sql` |
| 1.4 | Deploy `verify-proof` Edge Function | ❌ | `supabase functions deploy verify-proof --project-ref wxjtksxugsirpowptpmz` |
| 1.5 | Deploy `delete-account` Edge Function | ❌ | `supabase functions deploy delete-account --project-ref wxjtksxugsirpowptpmz` |
| 1.6 | Set `MISTRAL_API_KEY` env var on `verify-proof` function | ❌ | Supabase Dashboard → Edge Functions → verify-proof → Environment Variables |
| 1.7 | Set `MISTRAL_DAILY_LIMIT` env var (optional — defaults to 50) | ❌ | Same place as 1.6 |
| 1.8 | **Rotate the existing Mistral API key** in the Mistral console. The previous key was baked into an earlier build and was exposed in this repo's working tree (now scrubbed from `DEVELOPER_HANDOFF.md`, but the key string was live on disk). | ❌ | https://console.mistral.ai/ |
| 1.9 | Re-test sign-up → ensure RLS doesn't block the `parents` insert | ❌ | Manual: web app, fresh email |
| 1.10 | Create two-parent isolation test (account A can't read account B's children/photos) | ❌ | Manual: two real accounts, one login then the other |

## 2. Release signing (Android)

| # | Action | Status | Where |
|---|---|---|---|
| 2.1 | Generate a release keystore (one-time) | ❌ | `keytool -genkey -v -keystore ~/donefirst-upload.jks -alias donefirst -keyalg RSA -keysize 2048 -validity 10000` |
| 2.2 | Copy `android/key.properties.example` → `android/key.properties` and fill in storeFile, storePassword, keyAlias, keyPassword | ❌ | Local file |
| 2.3 | Place the `.jks` file somewhere not in the repo (or uncomment the ignore if it lives in `android/`) | ❌ | Local |
| 2.4 | Confirm `android/key.properties` and `*.jks` are in `.gitignore` | ✅ | `.gitignore` (committed in this branch) |
| 2.5 | Verify `flutter build apk --release` produces a signed APK | ❌ | Local |
| 2.6 | Verify `MainActivity.kt` is at `com/donefirst/app/` (was broken) | ✅ | `android/app/src/main/kotlin/com/donefirst/app/MainActivity.kt` |
| 2.7 | Fix Android `applicationId` from `com.example.donefirst` to `com.donefirst.app` | ✅ | `android/app/build.gradle.kts` |

## 3. iOS

| # | Action | Status | Where |
|---|---|---|---|
| 3.1 | Enroll in Apple Developer Program ($99/yr) | ❌ | https://developer.apple.com/programs/ |
| 3.2 | Change bundle ID from `com.example.donefirst` to `com.donefirst.app` in Xcode | ❌ | Xcode → Runner target → Signing & Capabilities |
| 3.3 | Request `com.apple.developer.family-controls` entitlement | ❌ | https://developer.apple.com/contact/request/family-controls — 2+ week review |
| 3.4 | Set up provisioning profiles | ❌ | Apple Developer portal |

## 4. Native app blocking (the core promise)

| # | Action | Status | Where |
|---|---|---|---|
| 4.1 | iOS: implement `FamilyControls` + `ManagedSettings` in Swift | ❌ | New Swift code in `ios/Runner/`; requires entitlement from 3.3 |
| 4.2 | Android: implement `AccessibilityService` + `UsageStats` permission | ❌ | New Kotlin code in `android/app/src/main/kotlin/` |
| 4.3 | Surface blocking errors — current code silently swallows them | ❌ | `lib/services/blocking_service.dart` |
| 4.4 | Have the kid-side app request permission on first run (currently only parent-side does) | ❌ | `lib/screens/lock_active_screen.dart` |

This is the largest remaining blocker — 4-7 weeks of native work, gated
on Apple Developer enrollment.

## 5. Legal & App Store

| # | Action | Status | Where |
|---|---|---|---|
| 5.1 | Legal review of `PRIVACY.md` and in-app policy copy | ❌ | Send to lawyer |
| 5.2 | Legal review of `TERMS.md` | ❌ | Send to lawyer |
| 5.3 | Add real parental-consent flow (current checkbox is attestation only, not consent capture) | ❌ | New screen + persisted consent record |
| 5.4 | Play Console → Data Safety declaration (use `PRIVACY.md` content) | ❌ | Play Console → App content → Data safety |
| 5.5 | App Store Connect → App Privacy details (use `PRIVACY.md` content) | ❌ | App Store Connect → App Privacy |
| 5.6 | Prepare App Store screenshots (6.7", 6.1", 5.5" iPhone + 12.9" iPad) | ❌ | Local |
| 5.7 | Prepare Play Store screenshots + feature graphic + 1024×500 banner | ❌ | Local |
| 5.8 | Write app descriptions (short + long) | ❌ | Local |

## 6. App-store submission

| # | Action | Status | Where |
|---|---|---|---|
| 6.1 | Create Play Console app entry, fill content rating questionnaire | ❌ | Play Console |
| 6.2 | Submit AAB (preferred over APK for Play) | ❌ | `flutter build appbundle --release` |
| 6.3 | Submit iOS build via Xcode or Transporter | ❌ | Xcode |
| 6.4 | Address any review feedback in test accounts (Google and Apple will need real accounts to click through) | ❌ | Reply in console |

## 7. Observability

| # | Action | Status | Where |
|---|---|---|---|
| 7.1 | Add Sentry (or similar) crash reporting | ⚠️ | Code is wired (sentry_flutter ^8.14.0). Build with `--dart-define=SENTRY_DSN=...` to enable. Create a Sentry project to get the DSN. |
| 7.2 | Set up Mistral usage/cost alert | ❌ | Mistral console → usage limits |
| 7.3 | Set up Supabase usage dashboard and budget alert | ❌ | Supabase Dashboard |

## 8. Optional polish (not blockers)

- ~~Data export feature (parents can download all their data)~~ — ✅ done in code (`lib/services/data_export_service.dart`, Settings → Your Data)
- 30-day retention purge job for `mistral_verification_log` — ✅ functions written in `retention_jobs.sql`; pg_cron scheduling is optional
- Scheduled job to clean up orphan `proof-photos` storage objects — ✅ `find_orphan_proof_photos()` function in `retention_jobs.sql`; bulk delete via Supabase Storage API
- ~~Co-parent invite accept/decline flow (model exists, no UI)~~ — ✅ done in code (`lib/screens/coparent_screen.dart` has Accept/Decline for received invites and Cancel for sent)
- Account deletion token confirmation screen

---

## Quick commands you'll need

```bash
# Supabase CLI (once installed: npm i -g supabase, then supabase login)
supabase functions deploy verify-proof --project-ref wxjtksxugsirpowptpmz
supabase functions deploy delete-account --project-ref wxjtksxugsirpowptpmz

# SQL Editor (run in order):
# 1. schema_migrations.sql  (migrations 1-6, likely already applied)
# 2. rls_policies.sql       (this branch's migration 7)

# Android release
flutter build appbundle --release

# Web smoke
flutter build web --no-tree-shake-icons
python -m http.server 8080 -d build\web
```
