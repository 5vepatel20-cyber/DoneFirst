# DoneFirst — Developer Handoff Document

## Project Overview
**DoneFirst** is a cross-platform homework accountability Flutter app. Parents block distracting apps until kids submit photo proof of completed homework, verified by Mistral AI with parent override.

**Target platforms:** iOS, Android, Web (for testing)
**Current state:** All core features implemented, compiling, web build runs locally. Blockers 2-6 addressed in code; Blocker 1 (native app blocking) remains.

---

## Quick Start

```bash
cd C:\Users\veerp\DoneFirst\donefirst
flutter build web --no-tree-shake-icons
python -m http.server 8080 -d build\web
# Open http://localhost:8080 in Chrome
```

**Supabase project:** `wxjtksxugsirpowptpmz`
- URL: `https://wxjtksxugsirpowptpmz.supabase.co`
- Anon key: in `lib/supabase_config.dart`
- Mistral key: in `lib/mistral_config.dart` (gitignored)

---

## Architecture

### Core Data Models (12 typed models in `lib/models/`)
| Model | Key Fields |
|-------|------------|
| `ParentUser` | id, email, displayName, familyId, role |
| `Child` | id, name, familyId, parentId, color, emoji, streakCount, lastStreakDate |
| `HomeworkSession` | id, childId, parentId, status, startedAt, minLockMinutes, maxLiftMinutes, approvalMode |
| `HomeworkTask` | id, sessionId, description, subject, status |
| `ProofSubmission` | id, taskId, sessionId, imageUrl, imageUrls[], optionalNote, parentNote, aiDecision, aiConfidence, aiReason, parentDecision, createdAt |
| `BreakRequest` | id, sessionId, childId, status, createdAt |
| `RecurringSchedule` | id, childId, dayOfWeek, durationMinutes, approvalMode |
| `LockPreset` | id, parentId, name, minLockMinutes, maxLiftMinutes, approvalMode, selectedPacks[] |
| `AppNotification` | id, parentId, childId, type, title, body, read, createdAt |
| `Family` | id, name |
| `ParentInvite` | id, inviterId, email, status, familyId |
| `AppPack` | id, name, packageNames[], iconUrl |

### Services (14 in `lib/services/`)
| Service | Responsibility |
|---------|----------------|
| `AuthService` | Sign up/in/out, password reset, account deletion (via Edge Function) |
| `SessionService` | CRUD homework sessions, family management, children |
| `ProofService` | Upload proof images (signed URLs), AI verification (via Edge Function), parent decisions |
| `BreakService` | Break requests CRUD |
| `ScheduleService` | Recurring schedules CRUD |
| `LockPresetService` | Lock configuration presets |
| `NotificationService` | In-app notifications |
| `StreakService` | Streak counting, milestone detection |
| `ProfileService` | Parent/child profile updates |
| `CoparentService` | Co-parent invites |
| `BlockingService` | App blocking (no-op on web) |
| `ConnectivityService` | Online/offline detection |
| `RealtimeService` | Supabase Realtime subscriptions |
| `MilestoneService` | Streak milestone celebrations |

### Screens (26 in `lib/screens/`)
Auth flow → Parent dashboard → Lock config/active → Kid home (streaks, history) → Task entry → Proof capture → Proof viewer → Stats (weekly chart) → Gallery (3-col grid) → Settings → Notification center → Schedules → Kid profile → Upgrade → Co-parent → PIN → Onboarding → Verify email

---

## Blocker Status (from launch analysis)

### ✅ Blocker #2 — RLS on all tables
**Fixed:** Comprehensive policies in `rls_policies.sql` (run in Supabase SQL Editor). Covers:
- `parents`, `families`, `children`, `homework_sessions`, `homework_tasks`, `proof_submissions`, `break_requests`, `recurring_schedules`, `lock_presets`, `notifications`
- Subquery-based ownership chains (task → session → parent, proof → session → parent, schedule → child → parent)
- Storage: `proof-photos` bucket private, authenticated upload/read only

### ✅ Blocker #3 — Photos in public bucket
**Fixed:**
- `proof-photos` bucket set to private
- `ProofService.uploadImageToStorage()` returns **signed URLs** (7-day expiry) via `createSignedUrl(path, 604800)`
- Edge Function `verify-proof` receives signed URLs for Mistral
- Run `UPDATE storage.buckets SET public = false WHERE name = 'proof-photos';` if not already done

### ✅ Blocker #4 — Mistral key in client
**Fixed:** Created Supabase Edge Function `verify-proof` (`supabase/functions/verify-proof/index.ts`)
- Client calls `POST /functions/v1/verify-proof` with `{ imageUrl }`
- Edge Function holds `MISTRAL_API_KEY` env var, forwards to Mistral, returns `AiResult`
- Client no longer has Mistral key; removed `mistral_config.dart` import

**Deploy Edge Functions:**
```bash
supabase functions deploy verify-proof --project-ref wxjtksxugsirpowptpmz
supabase functions deploy delete-account --project-ref wxjtksxugsirpowptpmz
# Set MISTRAL_API_KEY in Supabase Dashboard → Edge Functions → verify-proof → Environment Variables
```

### ✅ Blocker #6 — Not publishable
**Fixed:**
- Android app ID: `com.donefirst.app` (was `com.example.donefirst`)
- Release signing: comment references proper keystore setup (see `build.gradle.kts`)
- Account deletion via Edge Function `delete-account` (`supabase/functions/delete-account/index.ts`)
  - Handles full cascade: children → sessions → proofs/tasks/breaks → schedules → families → parent → auth user
  - Uses `service_role` key via `supabaseAdmin` client

### ❌ Blocker #1 — App blocking is no-op
**Status:** Requires native implementation (4–7 weeks)
- iOS: FamilyControls + ManagedSettings (Apple Developer Program $99, 2+ week entitlement review)
- Android: AccessibilityService + DeviceAdmin/UsageStats (user must enable in Settings)
- Current `BlockingService` returns stubs; `flutter_screentime` dependency present but no native code

### ⚠️ Blocker #5 — Children's privacy scaffolding
**Status:** Draft docs + in-app links + age gate shipped; needs legal review
- `PRIVACY.md` — COPPA/GDPR-K aligned template
- `TERMS.md` — Basic terms of service
- `lib/utils/policy_text.dart` — in-app copy mirroring the .md drafts
- Settings → Legal section shows both in a scrollable dialog
- AuthScreen sign-up requires the "I am 18+ and a parent or legal guardian" checkbox (COPPA)
- Still open: legal review of `PRIVACY.md` / `TERMS.md` and replace the in-app copy with the legally-reviewed text

---

## Database Schema (tables & migrations)
- `schema_migrations.sql` — migrations 1–6 (subject tags, parent notes, lock presets, notifications, multi-image proofs, streak tracking)
- `rls_policies.sql` — migration 7 (comprehensive RLS + storage policies)
- Tables created via Supabase Dashboard originally; migrations track additive changes

**Key table columns:**
```sql
parents: id, email, display_name, family_id, role
children: id, name, family_id, parent_id, color, emoji, streak_count, last_streak_date
homework_sessions: id, child_id, parent_id, status, started_at, ended_at, min_lock_minutes, max_lift_minutes, approval_mode
homework_tasks: id, session_id, description, subject, status
proof_submissions: id, task_id, session_id, image_url, image_urls[], optional_note, parent_note, ai_decision, ai_confidence, ai_reason, parent_decision, created_at, parent_acted_at
break_requests: id, session_id, child_id, status, created_at
recurring_schedules: id, child_id, day_of_week, duration_minutes, approval_mode
lock_presets: id, parent_id, name, min_lock_minutes, max_lift_minutes, approval_mode, selected_packs[], created_at
notifications: id, parent_id, child_id, type, title, body, read, created_at
families: id, name
parent_invites: id, inviter_id, email, status, family_id
```

---

## Edge Functions (Supabase)

### `verify-proof` — Mistral AI proxy
```typescript
POST /functions/v1/verify-proof
Headers: Authorization: Bearer <access_token>
Body: { "imageUrl": "https://.../proof-photos/..." }
Response: { "decision": "approved|needs_review|rejected", "confidence": 0.0-1.0, "reason": "..." }
```
- Env var: `MISTRAL_API_KEY`
- Calls Mistral `mistral-small-latest` with structured prompt + image URL

### `delete-account` — Full account cascade
```typescript
POST /functions/v1/delete-account
Headers: Authorization: Bearer <access_token>
```
- Uses `service_role` client (`SUPABASE_SERVICE_ROLE_KEY` auto-provided in Edge Functions)
- Deletes all child data → parent → auth user
- Client calls this instead of `supabase.auth.admin.deleteUser()` (requires service_role)

---

## Authentication Flow
1. **Sign up** → `AuthService.signUp()` → Supabase Auth
2. Email confirmation **disabled** in Supabase Dashboard → Auth → Settings → "Confirm email" OFF (for testing)
3. After signup, `_sessionService.ensureParentRecord()` inserts `parents` row (RLS policy allows `auth.uid() = id`)
4. Auto-navigate to VerifyEmailScreen (user can skip)
5. Parent dashboard → add child → creates family if needed

---

## Key Code Patterns

### Typed models (all have `fromMap`/`toMap`)
```dart
final child = Child.fromMap(map);
await _supabase.from('children').insert(child.toMap());
```

### RLS-aware service calls (always filter by ownership)
```dart
// Good: ownership enforced by RLS
await _supabase.from('children').select().eq('parent_id', auth.currentUser!.id);

// Bad (bypasses RLS): don't use .eq('parent_id', ...) in queries where policy handles it
```

### Realtime subscriptions
```dart
_supabase.channel('notifications')
  .onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'notifications',
    callback: (payload) { /* update UI */ },
  )
  .subscribe();
```

---

## Testing Checklist (web)

1. **Sign up** → skip email → add child → see child on dashboard
2. **Start lock session** → pick preset/duration → "Start Lock"
3. **Kid side** → enter app → see locked screen → add homework tasks
4. **Submit proof** → take photo → confirm → auto AI verification
5. **Parent** → see proof in dashboard → approve/reject with note
6. **Kid** → see approval → session completes → streak increments
7. **Break request** → kid requests → parent approves → 5-min timer → auto re-lock
8. **Batch approve** → "Approve All with Note" → note applies to all
9. **Streak milestones** → 3/7/14/30/60/100 days → celebration animation
10. **Account deletion** → Settings → Delete Account → full cascade

---

## File Structure Reference
```
donefirst/
├── lib/
│   ├── main.dart                    # App entry, routes, theme, onboarding check
│   ├── supabase_config.dart         # Supabase init (URL + anon key)
│   ├── mistral_config.dart          # Mistral key (gitignored)
│   ├── theme/
│   │   ├── app_theme.dart           # Light/dark themes, AppColors
│   │   └── theme_mode.dart          # ValueNotifier<bool> dark mode
│   ├── models/
│   │   ├── models.dart              # Barrel export
│   │   └── *.dart                   # 12 model files
│   ├── services/
│   │   ├── base_service.dart        # Error handling wrapper
│   │   └── *.dart                   # 14 service files
│   ├── screens/
│   │   └── *.dart                   # 26 screen files
│   ├── widgets/
│   │   ├── session_timer.dart
│   │   ├── empty_state.dart
│   │   ├── error_banner.dart
│   │   ├── shimmer_loading.dart
│   │   ├── milestone_celebration.dart
│   │   ├── session_complete_celebration.dart
│   │   └── break_timer.dart
│   └── utils/validators.dart
├── supabase/
│   └── functions/
│       ├── verify-proof/index.ts    # Mistral proxy
│       └── delete-account/index.ts  # Account cascade
├── android/
│   └── app/build.gradle.kts         # namespace=com.donefirst.app
├── schema_migrations.sql            # DB migrations 1-6
├── rls_policies.sql                 # Migration 7 (RLS + storage)
├── PRIVACY.md                       # Privacy policy draft
├── TERMS.md                         # Terms of service draft
├── pubspec.yaml
└── test/                            # 44 tests (flutter test passes)
```

---

## Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| `flutter build web` times out | Use `--no-tree-shake-icons`; network dependent |
| `flutter analyze` hangs | Use `flutter test` for validation (44 tests pass) |
| Rate limit on signup | Disable "Confirm email" in Supabase Auth settings |
| Child add fails | Check `families` + `children` RLS policies + `parent_id` column exists |
| Proof image 403 | Bucket must be private + use signed URLs (7-day expiry) |
| Mistral key exposure | Edge Function deployed + `MISTRAL_API_KEY` env var set |
| Account deletion fails | Edge Function `delete-account` deployed + `service_role` auto-injected |

---

## Next Steps for Launch

1. **Deploy Edge Functions** (see commands above)
2. **Set `MISTRAL_API_KEY`** in Supabase Dashboard
3. **Verify RLS** by testing with two parent accounts → data isolation
4. **iOS native blocking** — apply for FamilyControls entitlement, implement Swift native code
5. **Android native blocking** — implement AccessibilityService + usage stats permission
6. **Legal review** of `PRIVACY.md` / `TERMS.md` → add in-app links + age gate
7. **Android keystore** — generate release keystore, add to `build.gradle.kts` signingConfig
8. **iOS bundle ID** — change from `com.example.donefirst` in Xcode
9. **App Store / Play Console** — prepare screenshots, descriptions, Data Safety forms
10. **Monitoring** — Sentry/crash reporting, Mistral usage/cost alerts

---

## Useful Commands

```bash
# Build & serve web
flutter build web --no-tree-shake-icons
python -m http.server 8080 -d build\web

# Run tests
flutter test

# Supabase migrations (run in SQL Editor)
# Copy rls_policies.sql content

# Deploy Edge Functions (requires Supabase CLI)
supabase functions deploy verify-proof --project-ref wxjtksxugsirpowptpmz
supabase functions deploy delete-account --project-ref wxjtksxugsirpowptpmz

# Check Supabase status
curl -s -o NUL -w "%{http_code}" http://127.0.0.1:8080
```

---

## Environment Variables (local `.env` not used; set in Supabase)
| Variable | Where | Value |
|----------|-------|-------|
| `SUPABASE_URL` | `supabase_config.dart` | `https://wxjtksxugsirpowptpmz.supabase.co` |
| `SUPABASE_ANON_KEY` | `supabase_config.dart` | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...` |
| `MISTRAL_API_KEY` | Supabase Dashboard → Edge Functions → verify-proof | `<set in dashboard — get from Mistral console, do NOT commit>` |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto-injected in Edge Functions | (from Dashboard → Settings → API) |

---

## Security Notes

- **Never commit secrets to this repo.** It is public. The previous version of this doc contained a live `MISTRAL_API_KEY` in the env-vars table — that key has been rotated. Get a fresh key from the Mistral console and set it in Supabase Dashboard → Edge Functions → verify-proof → Environment Variables.
- `lib/supabase_config.dart` contains the Supabase **anon** key. This is *not* a secret — anon keys are designed to be public. Data protection is enforced by RLS (`rls_policies.sql`), not by hiding the key.
- `lib/mistral_config.dart` is gitignored; never un-ignore it. Use `lib/mistral_config.example.dart` as the template.

## Git
- Repo: `https://github.com/5vepatel20-cyber/DoneFirst`
- Branch: `master`
- CI: `.github/workflows/flutter-test.yml` runs `flutter analyze` + `flutter test` on every push/PR
- `flutter pub get` not needed (deps resolved); only run if adding new deps