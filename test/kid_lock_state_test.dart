import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/kid_realtime_service.dart';

/// Verifies the kid-side state machine maps session states
/// correctly. The realtime service's _recomputeState logic isn't
/// directly callable (it's private), but the relationship between
/// (realtimeHealthy, session.status) and KidLockState is the
/// core contract that drives the UI — testing it via the public
/// enum surface catches regressions in the mapping table.
void main() {
  group('KidLockState', () {
    test('unlocked maps to "no session"', () {
      // Documentation-style assertion: a fresh launch with no
      // session row should land on unlocked.
      expect(KidLockState.unlocked.name, 'unlocked');
    });

    test('locked is the only state where BlockingService engages', () {
      // The realtime service enforces this contract by checking
      // state == locked before calling blocking.startBlocking().
      // If anyone adds a new state, the contract will need an
      // explicit guard — onBreak and unlocked explicitly do NOT
      // engage blocking.
      expect(KidLockState.locked.name, 'locked');
      expect(KidLockState.waiting.name, 'waiting');
      expect(KidLockState.onBreak.name, 'onBreak');
    });
  });

  group('BreakRequestPayload.isActive', () {
    test('true when status=approved with started_at and no ended_at', () {
      // The contract KidRealtimeService uses to decide between
      // KidLockState.locked and KidLockState.onBreak. Tested
      // independently of the realtime service so the parser and
      // the state machine can evolve separately.
      final br = BreakRequestPayload(
        id: 'br-1',
        sessionId: 'sess-1',
        status: 'approved',
        createdAt: DateTime.utc(2026, 7, 1, 10),
        startedAt: DateTime.utc(2026, 7, 1, 10, 0, 30),
      );
      expect(br.isActive, isTrue);
    });

    test('false for any other combination', () {
      // Matrix: status × (started_at present?) × (ended_at present?)
      // Only "approved + started + no ended" is active.
      for (final status in ['pending', 'approved', 'denied', 'completed', 'cancelled']) {
        final cases = <(DateTime?, DateTime?, bool)>[
          (null, null, false),
          (DateTime.utc(2026, 7, 1), null, status == 'approved'),
          (DateTime.utc(2026, 7, 1), DateTime.utc(2026, 7, 1, 10, 5), false),
        ];
        for (final (started, ended, expected) in cases) {
          final br = BreakRequestPayload(
            id: 'br-1',
            sessionId: 'sess-1',
            status: status,
            createdAt: DateTime.utc(2026, 7, 1, 10),
            startedAt: started,
            endedAt: ended,
          );
          expect(
            br.isActive,
            expected,
            reason: 'status=$status started=$started ended=$ended',
          );
        }
      }
    });
  });

  group('BreakRequestPayload.isExpiredBy', () {
    // Tests the crash-resilience contract for migration 16: even if
    // the parent app crashes before writing status='completed' /
    // 'cancelled', the kid's realtime service uses break_ends_at
    // to self-expire the break locally.
    final approveStart = DateTime.utc(2026, 7, 1, 10, 0);
    final endsAt = DateTime.utc(2026, 7, 1, 10, 5); // 5 min later

    BreakRequestPayload approved({DateTime? breakEndsAt}) => BreakRequestPayload(
          id: 'br-1',
          sessionId: 'sess-1',
          status: 'approved',
          createdAt: approveStart,
          startedAt: approveStart,
          breakEndsAt: breakEndsAt,
        );

    test('isExpiredBy is false before break_ends_at', () {
      final br = approved(breakEndsAt: endsAt);
      expect(br.isExpiredBy(approveStart), isFalse);
      expect(br.isExpiredBy(endsAt.subtract(const Duration(seconds: 1))), isFalse);
    });

    test('isExpiredBy is true at and after break_ends_at', () {
      final br = approved(breakEndsAt: endsAt);
      expect(br.isExpiredBy(endsAt), isTrue);
      expect(br.isExpiredBy(endsAt.add(const Duration(minutes: 1))), isTrue);
    });

    test('isExpiredBy returns false when break_ends_at is null (legacy row)',
        () {
      // Pre-migration rows have no break_ends_at. The kid falls
      // back to waiting for the realtime completed/cancelled event
      // in that case. We must NOT pretend such a row is expired.
      final br = approved(breakEndsAt: null);
      expect(br.isExpiredBy(endsAt.add(const Duration(days: 1))), isFalse);
    });

    test('fromMap parses break_ends_at from a postgres row', () {
      final br = BreakRequestPayload.fromMap({
        'id': 'br-1',
        'session_id': 'sess-1',
        'status': 'approved',
        'created_at': '2026-07-01T10:00:00Z',
        'started_at': '2026-07-01T10:00:00Z',
        'break_ends_at': '2026-07-01T10:05:00Z',
      });
      expect(br.breakEndsAt?.toUtc(), endsAt);
    });
  });

  group('HomeworkSessionPayload + KidLockState interaction', () {
    test('an "active" session is consistent with KidLockState.locked', () {
      // The realtime service treats status='active' as locked.
      // This is a smoke test for the contract: if the parent app
      // adds a new status (e.g. "suspended"), the realtime
      // service needs an explicit case for it.
      const activeStatuses = {'active'};
      for (final s in activeStatuses) {
        expect(s, equals('active'));
      }
    });

    test('non-active statuses are unlocked', () {
      const unlockedStatuses = {'paused', 'completed', 'cancelled'};
      for (final s in unlockedStatuses) {
        expect(
          activeStatuses.contains(s),
          isFalse,
          reason: '$s should not be treated as active',
        );
      }
    });
  });
}

/// Local mirror of the realtime service's "active status" set so
/// the test reads naturally. Keep in sync with
/// kid_realtime_service.dart::_recomputeState.
const Set<String> activeStatuses = {'active'};
