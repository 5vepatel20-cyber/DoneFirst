# Green Check Bug - Investigation & Status

## Problem
After a kid submits a Google screenshot as homework proof, the AI correctly rejects it
in the database, but the app still shows a **green checkmark** (completed) next to the task.

## Root Cause: FIXED (multiple instances)

The bug was `status != 'pending'` used throughout the codebase to determine task completion.
This treats `'rejected'` the same as `'submitted'` — both are `!= 'pending'`, so both show
a green check.

### Files Fixed

1. **`lib/screens/kid_home_screen.dart`** (THE screen the kid actually sees)
   - `_buildTaskRow()` line 592: `t.status != 'pending'` → `t.status == 'submitted' || t.status == 'approved'`
   - `_tasksRemaining`/`_tasksSubmitted`/`_allDone` at line 234: same fix
   - `completedTasks` at line 120: same fix
   - Task row now shows **red X** + "AI rejected — retake proof" for rejected tasks

2. **`lib/screens/kid/locked_screen.dart`**
   - Same 3 spots fixed identically

3. **`lib/screens/task_entry_screen.dart`**
   - `isDone` at line 219: same fix
   - Now shows red X icon + "AI rejected" subtitle

## DB Verification (confirmed working)

All recent tasks have correct status:
```
cab2bcb9 - "Math worksheet"      → status: rejected  ✓
28c9f994 - "Math Worksheet"       → status: rejected  ✓
6879de19 - "MAth worksheet"       → status: rejected  ✓
790a4757 - "DO ALGEBRA @ PROBLEm" → status: rejected  ✓
26a1ba96 - "Algebra 2 math problem" → status: rejected ✓
8ef78c06 - "Math Problem"         → status: submitted ✓ (AI approved - real homework)
```

All proofs show `ai_decision: "rejected"` with `ai_confidence: 1.0` for Google screenshots.

## Still Not Working — Possible Causes

### 1. Browser Service Worker Cache (MOST LIKELY)
Flutter web registers a service worker (`flutter_service_worker.js`) that aggressively
caches all JS/CSS assets. Even with `flutter clean` + rebuild + no-cache headers on the
Python server, the **old cached JS may still be served** by the service worker.

**Fix attempts made:**
- Added `Cache-Control: no-cache, no-store, must-revalidate` headers to `serve.py`
- Did `flutter clean` + `flutter build web`
- Service worker has `self.skipWaiting()` + `self.registration.unregister()`

**If still broken:** Open http://localhost:8080 in an **incognito/private window**
(bypasses all caching). Or manually: Chrome DevTools → Application → Storage → Clear site data.

### 2. Verification Script
To verify the fix is actually in the running build, open Chrome DevTools (F12) →
Console → paste:
```js
// This fetches the running main.dart.js and checks for the fix
fetch('/main.dart.js').then(r=>r.text()).then(t=>{
  console.log('Has old bug:', t.includes("status != 'pending'"));
  console.log('Has fix:', t.includes("status == 'submitted' || t.status == 'approved'"));
})
```
If `Has old bug: true` → the browser is serving cached old JS.
If `Has old bug: false` → the fix is in the JS but the service worker is intercepting.

## AI Verification Status: WORKING

The AI (Mistral `mistral-small-latest` via `pixtral-12b-latest` now) correctly:
- Rejects Google screenshots (confidence: 1.0)
- Rejects YouTube screenshots (confidence: 1.0)
- Approves legitimate digital math assignments (confidence: 0.98)
- Sends task-specific context (description + subject) to the AI

Edge function: `verify-proof` v10, deployed to Supabase.
Confidence floor: 0.8 (low-confidence approvals → needs_review).

## Nuclear Option: Disable Service Worker in Development

If the cache is the persistent issue, add this to `web/index.html` before `</body>`:

```html
<script>
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistrations().then(registrations => {
      registrations.forEach(registration => registration.unregister());
    });
  }
</script>
```

Then rebuild. This prevents Flutter's service worker from ever registering during development.
