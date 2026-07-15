import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/screens/lock_active_screen.dart';

/// Unit tests for the auto-lift safety-net decision in
/// LockActiveScreen.shouldAutoLiftNow.
///
/// The full auto-lift flow is widget-tree-heavy (calls _unlock,
/// navigates to the celebration screen, inserts a notification),
/// but the trigger logic is a pure function we can drive directly
/// here. This guards against regressions in the "did the safety
/// net actually fire when the parent walked away?" contract.
void main() {
  group('LockActiveScreen.shouldAutoLiftNow', () {
    final start = DateTime.utc(2026, 7, 1, 10);

    test('returns false when maxLiftMinutes is null', () {
      // Legacy sessions (or a parent who set min=max) shouldn't
      // auto-lift — the safety net is opt-in via the max_lift
      // column being non-null.
      expect(
        LockActiveScreen.shouldAutoLiftNow(
          startedAt: start,
          maxLiftMinutes: null,
          now: start.add(const Duration(hours: 5)),
        ),
        isFalse,
      );
    });

    test('returns false when maxLiftMinutes is zero', () {
      expect(
        LockActiveScreen.shouldAutoLiftNow(
          startedAt: start,
          maxLiftMinutes: 0,
          now: start.add(const Duration(hours: 5)),
        ),
        isFalse,
      );
    });

    test('returns false when now is before startedAt + maxLift', () {
      expect(
        LockActiveScreen.shouldAutoLiftNow(
          startedAt: start,
          maxLiftMinutes: 60,
          now: start.add(const Duration(minutes: 30)),
        ),
        isFalse,
      );
    });

    test('returns false at exactly the boundary (one tick early)', () {
      // The decision fires when now >= autoLiftAt. A test one
      // millisecond short should return false so the parent's
      // own "End Lock" tap gets the cleaner 'finished' reason
      // rather than racing the auto-lift.
      final limit = start.add(const Duration(minutes: 60));
      expect(
        LockActiveScreen.shouldAutoLiftNow(
          startedAt: start,
          maxLiftMinutes: 60,
          now: limit.subtract(const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
    });

    test('returns true at exactly the boundary', () {
      final limit = start.add(const Duration(minutes: 60));
      expect(
        LockActiveScreen.shouldAutoLiftNow(
          startedAt: start,
          maxLiftMinutes: 60,
          now: limit,
        ),
        isTrue,
      );
    });

    test('returns true well past the limit', () {
      expect(
        LockActiveScreen.shouldAutoLiftNow(
          startedAt: start,
          maxLiftMinutes: 60,
          now: start.add(const Duration(hours: 3)),
        ),
        isTrue,
      );
    });

    test('handles maxLiftMinutes = minLockMinutes (immediate lift after min)',
        () {
      // Default preset has max == 120 with min == some value. A
      // parent who sets them equal wants the lock to end the
      // moment the minimum is satisfied — effectively "lock until
      // they hit min". shouldAutoLiftNow should fire when the
      // single boundary is reached.
      expect(
        LockActiveScreen.shouldAutoLiftNow(
          startedAt: start,
          maxLiftMinutes: 30,
          now: start.add(const Duration(minutes: 30)),
        ),
        isTrue,
      );
    });
  });
}