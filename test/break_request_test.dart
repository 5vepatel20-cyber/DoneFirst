import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/models/break_request.dart';

/// Unit tests for the BreakRequest model. Covers the new
/// `isActiveBreak` getter that's the kid app's source of truth
/// for "am I currently on a break?" — the field that drives
/// KidLockState.onBreak vs KidLockState.locked.
void main() {
  BreakRequest make({
    String status = 'pending',
    DateTime? startedAt,
    DateTime? endedAt,
  }) =>
      BreakRequest(
        id: 'br-1',
        sessionId: 'sess-1',
        childId: 'child-1',
        status: status,
        createdAt: DateTime.utc(2026, 7, 1, 10),
        startedAt: startedAt,
        endedAt: endedAt,
      );

  group('BreakRequest.isActiveBreak', () {
    test('true when approved with started_at and no ended_at', () {
      final br = make(
        status: 'approved',
        startedAt: DateTime.utc(2026, 7, 1, 10, 0, 30),
      );
      expect(br.isActiveBreak, isTrue);
    });

    test('false when approved but started_at is null', () {
      // Belt-and-suspenders: a status flip that landed before the
      // started_at write. The parent service sets them in the
      // same UPDATE, but RLS or partial-failure could leave them
      // out of sync. Don't drive the lock off a row with no
      // started_at — the kid would never know when the break
      // started.
      final br = make(status: 'approved');
      expect(br.isActiveBreak, isFalse);
    });

    test('false when approved with ended_at already set', () {
      // End-of-break write landed but status='approved' is stale.
      // isActiveBreak should drop it.
      final br = make(
        status: 'approved',
        startedAt: DateTime.utc(2026, 7, 1, 10, 0, 30),
        endedAt: DateTime.utc(2026, 7, 1, 10, 5),
      );
      expect(br.isActiveBreak, isFalse);
    });

    test('false for terminal statuses (completed/cancelled/denied)', () {
      for (final s in ['completed', 'cancelled', 'denied']) {
        final br = make(
          status: s,
          startedAt: DateTime.utc(2026, 7, 1, 10),
        );
        expect(br.isActiveBreak, isFalse, reason: 'status=$s should be inactive');
      }
    });

    test('false for pending (parent has not decided yet)', () {
      final br = make(status: 'pending');
      expect(br.isActiveBreak, isFalse);
    });
  });

  group('BreakRequest.fromMap', () {
    test('parses the new started_at and ended_at columns', () {
      final br = BreakRequest.fromMap({
        'id': 'br-1',
        'session_id': 'sess-1',
        'child_id': 'child-1',
        'status': 'approved',
        'created_at': '2026-07-01T10:00:00Z',
        'started_at': '2026-07-01T10:00:30Z',
        'ended_at': null,
      });
      expect(br.startedAt, DateTime.utc(2026, 7, 1, 10, 0, 30));
      expect(br.endedAt, isNull);
      expect(br.isActiveBreak, isTrue);
    });

    test('tolerates missing started_at/ended_at on legacy rows', () {
      // Rows written before migration_15 won't have the new
      // columns. fromMap should not throw — nullable.
      final br = BreakRequest.fromMap({
        'id': 'br-1',
        'session_id': 'sess-1',
        'child_id': 'child-1',
        'status': 'completed',
        'created_at': '2026-07-01T10:00:00Z',
      });
      expect(br.startedAt, isNull);
      expect(br.endedAt, isNull);
    });
  });
}
