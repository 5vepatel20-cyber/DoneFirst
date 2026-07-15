import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/services/pin_attempt_tracker.dart';

/// Pins the contract that `PinGuard.confirmInline` shares its
/// attempt counter with the full-screen `PinScreen`. Both flows
/// hit the same SharedPreferences keys (pin_attempts_v1,
/// pin_lockout_until_v1) — that's what prevents a kid from
/// brute-forcing the 4-digit PIN by alternating between the two
/// surfaces.
///
/// These tests don't drive the dialog itself (that's a widget
/// test surface); they verify the shared-counter contract by
/// showing the tracker state transitions that the inline flow
/// relies on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Inline lockout contract', () {
    late PinAttemptTracker tracker;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tracker = PinAttemptTracker();
    });

    test('5 wrong entries trigger lockout regardless of source', () async {
      // Simulates the inline path: user enters wrong PIN 5 times.
      // Each failure is recorded via the same tracker the full-
      // screen gate uses, so by the 5th attempt the gate is locked
      // for the next caller too.
      for (var i = 0; i < PinAttemptTracker.maxAttempts; i++) {
        await tracker.recordFailure();
      }
      expect(await tracker.isLockedOut(), isTrue);
      expect(await tracker.remainingLockoutSeconds(), greaterThan(0));
    });

    test('correct entry resets counter so lockout does not trigger',
        () async {
      // Simulates: 4 wrong, then correct. The inline flow calls
      // reset() on match — without that, a parent who fat-fingered
      // once would be one wrong entry away from lockout.
      for (var i = 0; i < PinAttemptTracker.maxAttempts - 1; i++) {
        await tracker.recordFailure();
      }
      expect(await tracker.failedAttempts(),
          PinAttemptTracker.maxAttempts - 1);
      await tracker.reset();
      expect(await tracker.failedAttempts(), 0);
      expect(await tracker.isLockedOut(), isFalse);
    });

    test('a single tracker instance sees failures across flow switches',
        () async {
      // The whole point of the shared counter: a kid who burns 4
      // attempts on the full-screen gate then switches to an
      // inline prompt sees the same counter. Here we simulate by
      // calling recordFailure 4 times (full-screen), then check
      // that a fresh read still shows 4 attempts (i.e. the inline
      // path would see "1 try left" rather than "5 tries left").
      for (var i = 0; i < 4; i++) {
        await tracker.recordFailure();
      }
      // Brand-new tracker instance reads from the same prefs.
      final otherView = PinAttemptTracker();
      expect(await otherView.failedAttempts(), 4);
    });
  });
}