import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/kid_realtime_service.dart';

/// Unit tests for HomeworkSessionPayload.fromMap.
///
/// The kid app's realtime listener parses incoming postgres_changes
/// payloads into HomeworkSessionPayload. The parent app's schema is
/// authoritative — if a field name changes there, these tests will
/// fail loudly instead of producing silently-wrong UI.
void main() {
  group('HomeworkSessionPayload.fromMap', () {
    test('parses a typical active session row', () {
      final map = {
        'id': 'sess-123',
        'child_id': 'child-456',
        'status': 'active',
        'min_lock_minutes': 30,
        'started_at': '2026-07-11T10:00:00Z',
        'ended_at': null,
      };
      final p = HomeworkSessionPayload.fromMap(map);
      expect(p.id, 'sess-123');
      expect(p.childId, 'child-456');
      expect(p.status, 'active');
      expect(p.minLockMinutes, 30);
      expect(p.startedAt.toUtc(), DateTime.utc(2026, 7, 11, 10));
      expect(p.endedAt, isNull);
    });

    test('parses a completed session with ended_at', () {
      final map = {
        'id': 'sess-789',
        'child_id': 'child-456',
        'status': 'completed',
        'min_lock_minutes': 60,
        'started_at': '2026-07-11T10:00:00Z',
        'ended_at': '2026-07-11T11:00:00Z',
      };
      final p = HomeworkSessionPayload.fromMap(map);
      expect(p.status, 'completed');
      expect(p.endedAt?.toUtc(), DateTime.utc(2026, 7, 11, 11));
    });

    test('defaults status to "active" when missing', () {
      // Defensive against schema drift — if postgres_changes ever
      // delivers a partial payload, we want a sane default.
      final p = HomeworkSessionPayload.fromMap({
        'id': 'sess-1',
        'child_id': 'c',
        'min_lock_minutes': 0,
        'started_at': '2026-07-11T10:00:00Z',
      });
      expect(p.status, 'active');
    });

    test('falls back to now() on unparseable started_at', () {
      // DateTime.tryParse returns null on garbage; we substitute
      // DateTime.now() rather than throw, so the UI never crashes
      // mid-session.
      final before = DateTime.now();
      final p = HomeworkSessionPayload.fromMap({
        'id': 'sess-1',
        'child_id': 'c',
        'status': 'active',
        'min_lock_minutes': 0,
        'started_at': 'not-a-date',
      });
      final after = DateTime.now();
      expect(
        p.startedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        p.startedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('min_lock_minutes defaults to 0 when missing', () {
      final p = HomeworkSessionPayload.fromMap({
        'id': 'sess-1',
        'child_id': 'c',
        'status': 'active',
        'started_at': '2026-07-11T10:00:00Z',
      });
      expect(p.minLockMinutes, 0);
    });
  });
}
