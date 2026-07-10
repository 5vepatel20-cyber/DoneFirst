import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/services/pin_attempt_tracker.dart';

/// Tests for the rate-limit logic that keeps a kid from brute-forcing
/// the 4-digit parent PIN. We mock SharedPreferences so the tracker
/// persists across "calls" without touching real storage, and we
/// drive the clock with a helper that lets us jump forward without
/// sleeping.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PinAttemptTracker', () {
    late PinAttemptTracker tracker;

    setUp(() async {
      // Each test starts with a fresh prefs instance so counters
      // and lockouts from a prior test don't leak.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tracker = PinAttemptTracker();
    });

    test('starts unlocked with zero failed attempts', () async {
      expect(await tracker.isLockedOut(), isFalse);
      expect(await tracker.failedAttempts(), 0);
      expect(await tracker.remainingLockoutSeconds(), 0);
    });

    test('recordFailure increments the attempt counter', () async {
      await tracker.recordFailure();
      expect(await tracker.failedAttempts(), 1);
      await tracker.recordFailure();
      expect(await tracker.failedAttempts(), 2);
    });

    test(
      'does not lock out until maxAttempts failures have been recorded',
      () async {
        for (var i = 0; i < PinAttemptTracker.maxAttempts - 1; i++) {
          await tracker.recordFailure();
        }
        expect(await tracker.isLockedOut(), isFalse);
      },
    );

    test(
      'locks out on the maxAttempts-th failure and exposes the remaining '
      'lockout window',
      () async {
        for (var i = 0; i < PinAttemptTracker.maxAttempts; i++) {
          await tracker.recordFailure();
        }
        expect(await tracker.isLockedOut(), isTrue);
        // Default lockoutDuration is 30s — first reading should be
        // close to the full window, but allow a small amount of
        // jitter from the test clock advancing.
        final remaining = await tracker.remainingLockoutSeconds();
        expect(remaining, greaterThan(0));
        expect(remaining, lessThanOrEqualTo(PinAttemptTracker.lockoutDuration.inSeconds));
      },
    );

    test('reset() clears both counter and lockout', () async {
      for (var i = 0; i < PinAttemptTracker.maxAttempts; i++) {
        await tracker.recordFailure();
      }
      expect(await tracker.isLockedOut(), isTrue);
      await tracker.reset();
      expect(await tracker.isLockedOut(), isFalse);
      expect(await tracker.failedAttempts(), 0);
    });

    test('isLockedOut returns false and clears counter when lockout expired',
        () async {
      // Pre-arm a lockout that's already in the past so the next
      // isLockedOut() call falls into the "expired" branch.
      SharedPreferences.setMockInitialValues({
        'pin_attempts_v1': PinAttemptTracker.maxAttempts,
        'pin_lockout_until_v1':
            DateTime.now().millisecondsSinceEpoch - 1000,
      });
      final t = PinAttemptTracker();
      expect(await t.isLockedOut(), isFalse);
      // Side effect: counter cleared so the kid gets a fresh
      // maxAttempts more tries.
      expect(await t.failedAttempts(), 0);
    });

    test('remainingLockoutSeconds returns 0 when not locked out', () async {
      expect(await tracker.remainingLockoutSeconds(), 0);
    });

    test('debugForceClear is equivalent to reset', () async {
      for (var i = 0; i < PinAttemptTracker.maxAttempts; i++) {
        await tracker.recordFailure();
      }
      await tracker.debugForceClear();
      expect(await tracker.isLockedOut(), isFalse);
      expect(await tracker.failedAttempts(), 0);
    });
  });
}
