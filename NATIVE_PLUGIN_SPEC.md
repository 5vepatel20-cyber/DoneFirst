# Native Plugin Specification — flutter_screentime

The Flutter side calls three methods on the `flutter_screentime` plugin
(see `lib/services/blocking_service.dart`). The native side must implement
each of these so the method-channel calls resolve.

This file is the contract. If you change anything here, change the
implementation in `ios/Runner/` and `android/app/src/main/kotlin/` to
match.

---

## Method 1: `requestAuthorization`

**Signature (Dart):**
```dart
await plugin.requestAuthorization()   // → Future<void>
```

**iOS implementation:**
- Trigger `AuthorizationCenter.shared.requestAuthorization(for: .child)`
  inside a `ManagedSettingsStore`-aware view controller.
- Must return after the user has either granted or denied; the Dart
  side does not block on a long-running callback, just awaits the
  single channel response.
- If granted, store the resulting authorization state where your
  start-blocking implementation can read it.
- If denied, the Dart side moves to `BlockingStatus.permissionDenied`
  and the UI prompts the user to fix it in Settings.

**Android implementation:**
- Open the UsageStats settings page (`Settings.ACTION_USAGE_ACCESS_SETTINGS`)
  via an `Intent` and also open the Accessibility settings page
  (`Settings.ACTION_ACCESSIBILITY_SETTINGS`) so the user can grant both
  in one flow.
- Your `AccessibilityService` must subclass
  `androidx.appcompat.view.AccessibilityService` (or the equivalent
  in your chosen Kotlin lifecycle), declare the
  `BIND_ACCESSIBILITY_SERVICE` permission in AndroidManifest.xml,
  and declare the AccessibilityService with the
  `android.accessibilityservice` intent-filter in metadata.
- Detect both grants when your service's `onServiceConnected` fires
  and write a flag you can read from start-blocking.

**Both platforms must:**
- Throw a `PlatformException` with code `permission_denied` when the
  user explicitly denies, or `not_available` when the device cannot
  support blocking (e.g. parental-controls disabled by MDM).

---

## Method 2: `startBlocking`

**Signature (Dart):**
```dart
await plugin.startBlocking()   // → Future<void>
```

This must be called only AFTER `requestAuthorization` has returned
without throwing. The Dart side enforces that gate, but the native side
should also assert on its end.

**iOS implementation:**
- Apply a `ManagedSettings` ShieldConfiguration to all currently-
  installed applications in the managed family. Use
  `FamilyActivitySelection` to limit the shield to the apps the parent
  chose during setup (see the `selected_apps` field in the lock_presets
  table — the Flutter side does not currently pass this; the native
  side should default to shielding ALL apps in the family until we wire
  that through).
- The shield should use category `ShieldActionCategoryBlock` (or
  equivalent) and provide a localized message ("Apps are blocked.
  Finish your homework to unlock.").
- Throw a `PlatformException` with code `shield_failed` if
  `ManagedSettingsStore.shield.applications` throws.

**Android implementation:**
- From your `AccessibilityService`, override `onAccessibilityEvent`
  and detect `TYPE_WINDOW_STATE_CHANGED` for the foreground app.
- When the foreground app is in the blocklist, call
  `performGlobalAction(GLOBAL_ACTION_HOME)` to send the user back to
  the home screen, or launch your own full-screen "blocked" activity.
- Use `UsageStatsManager.queryEvents` to detect which apps are
  being launched; populate a HashSet<String> of package names to
  block. The Flutter side does not currently pass this list; the
  native side should default to blocking all apps except the system
  ones (Phone, Settings, your own app).
- Throw a `PlatformException` with code `accessibility_lost` if your
  service is no longer connected (e.g. user disabled it from
  Settings). The Dart side will surface this as
  `BlockingStatus.blockingFailed` and the banner tells the parent
  to re-enable it.

**Both platforms must:**
- Be idempotent — calling `startBlocking` when already blocking should
  not throw. It should succeed as a no-op.
- Persist the blocking state across app restarts. If the user kills
  the parent app, blocking should continue until `stopBlocking` is
  called.

---

## Method 3: `stopBlocking`

**Signature (Dart):**
```dart
await plugin.stopBlocking()   // → Future<void>
```

**iOS implementation:**
- Call `ManagedSettingsStore.shield.applications = nil` (or
  equivalent clear) and remove the shield.

**Android implementation:**
- Clear your blocklist HashSet. Stop intercepting events.

**Both platforms must:**
- Be idempotent and never throw on a no-op.

---

## Channel configuration

The plugin uses a `MethodChannel` named `flutter_screentime`. The Dart
side calls `MethodChannel.invokeMethod('requestAuthorization' | 'startBlocking' | 'stopBlocking')` with no arguments.

If you need to add new methods (e.g. to read the current blocklist or
push a specific app list down from Flutter), extend `FlutterScreentime.kt`
and `.swift` together with new methods in the same channel.

---

## Testing checklist

Before declaring the native side "done" for a platform:

- [ ] First-run `requestAuthorization` opens the OS dialog.
- [ ] If granted, `startBlocking` succeeds and the kid sees apps
      blocked when they try to open another app.
- [ ] If denied, the Dart `BlockingStatus.permissionDenied` is set
      and the UI shows the banner with "open Settings" affordance.
- [ ] Calling `stopBlocking` releases the shield / clear the
      blocklist and the kid can open other apps.
- [ ] Kill and restart the app: blocking persists across restarts.
- [ ] Revoke the permission mid-block (e.g. from Settings): the
      Dart side surfaces an error banner.
- [ ] Native method does not block the UI thread for > 100 ms on a
      low-end device (Android Go target).

---

## Time estimate

This is the single biggest blocker on the launch checklist. Both
platforms are 4-6 weeks of focused work for a developer who has done
either FamilyControls or Android AccessibilityService before.

- **iOS:** ~3 weeks for a developer familiar with Swift +
  ManagedSettings. FamilyControls entitlement review (Apple side)
  adds 2+ weeks of calendar time on top.
- **Android:** ~2 weeks for a developer familiar with Kotlin +
  AccessibilityService. No entitlement review, but the Accessibility
  Service is notoriously fragile across OEM skins.

Until this lands, the app is a "homework tracking + photo proof +
messaging" app, not a "device lock" app. The rest of the value
proposition works.
