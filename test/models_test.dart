import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/models/models.dart';

void main() {
  group('Child', () {
    test('fromMap parses correctly', () {
      final c = Child.fromMap({
        'id': 'c1',
        'name': 'Alice',
        'family_id': 'f1',
        'parent_id': 'p1',
        'color': 'blue',
        'emoji': '👧',
        'streak_count': 3,
        'last_streak_date': '2026-07-06T12:00:00Z',
      });
      expect(c.id, 'c1');
      expect(c.name, 'Alice');
      expect(c.familyId, 'f1');
      expect(c.parentId, 'p1');
      expect(c.color, 'blue');
      expect(c.emoji, '👧');
      expect(c.streakCount, 3);
      expect(c.lastStreakDate, isNotNull);
    });

    test('fromMap handles null fields', () {
      final c = Child.fromMap({'id': 'c2', 'name': 'Bob'});
      expect(c.familyId, isNull);
      expect(c.streakCount, 0);
      expect(c.lastStreakDate, isNull);
    });

    test('toMap round-trips', () {
      final c = Child(
        id: 'c3',
        name: 'Charlie',
        familyId: 'f1',
        parentId: 'p1',
        color: 'red',
        emoji: '👦',
        streakCount: 5,
        lastStreakDate: DateTime(2026, 7, 6),
      );
      final map = c.toMap();
      final c2 = Child.fromMap(map);
      expect(c2.id, c.id);
      expect(c2.name, c.name);
      expect(c2.streakCount, c.streakCount);
    });
  });

  group('HomeworkSession', () {
    test('status helpers', () {
      final active = HomeworkSession.fromMap({
        'id': 's1',
        'child_id': 'c1',
        'parent_id': 'p1',
        'status': 'active',
        'started_at': '2026-07-06T12:00:00Z',
        'min_lock_minutes': 60,
      });
      expect(active.isActive, isTrue);
      expect(active.isPaused, isFalse);
      expect(active.isCompleted, isFalse);

      final paused = HomeworkSession.fromMap({
        'id': 's2',
        'child_id': 'c1',
        'parent_id': 'p1',
        'status': 'paused',
        'started_at': '2026-07-06T12:00:00Z',
      });
      expect(paused.isPaused, isTrue);

      final done = HomeworkSession.fromMap({
        'id': 's3',
        'child_id': 'c1',
        'parent_id': 'p1',
        'status': 'completed',
        'started_at': '2026-07-06T12:00:00Z',
      });
      expect(done.isCompleted, isTrue);
    });
  });

  group('HomeworkTask', () {
    test('status helpers', () {
      final pending = HomeworkTask.fromMap({
        'id': 't1',
        'session_id': 's1',
        'description': 'Math worksheet',
      });
      expect(pending.isPending, isTrue);
      expect(pending.isSubmitted, isFalse);

      final submitted = HomeworkTask.fromMap({
        'id': 't2',
        'session_id': 's1',
        'description': 'Reading',
        'status': 'submitted',
      });
      expect(submitted.isSubmitted, isTrue);

      final approved = HomeworkTask.fromMap({
        'id': 't3',
        'session_id': 's1',
        'description': 'Essay',
        'status': 'approved',
      });
      expect(approved.isApproved, isTrue);
    });
  });

  group('ProofSubmission', () {
    test('status helpers and multi-photo', () {
      final p = ProofSubmission.fromMap({
        'id': 'p1',
        'task_id': 't1',
        'image_url': 'https://example.com/photo.jpg',
        'image_urls': ['https://example.com/photo.jpg',
            'https://example.com/photo2.jpg'],
        'parent_decision': 'pending',
        'created_at': '2026-07-06T12:00:00Z',
      });
      expect(p.isPending, isTrue);
      expect(p.isApproved, isFalse);
      expect(p.hasMultiplePhotos, isTrue);
      expect(p.imageUrls.length, 2);
    });

    test('AiResult fromJson', () {
      final ai = AiResult.fromJson({
        'decision': 'approved',
        'confidence': 0.95,
        'reason': 'Shows completed worksheet',
      });
      expect(ai.isApproved, isTrue);
      expect(ai.confidence, 0.95);
      expect(ai.reason, 'Shows completed worksheet');
    });
  });

  group('RecurringSchedule', () {
    test('dayName returns correct names', () {
      final mon = RecurringSchedule(
        id: 'r1',
        childId: 'c1',
        dayOfWeek: 0,
      );
      expect(mon.dayName, 'Mon');

      final sun = RecurringSchedule(
        id: 'r2',
        childId: 'c1',
        dayOfWeek: 6,
      );
      expect(sun.dayName, 'Sun');
    });
  });

  group('ParentInvite', () {
    test('status helpers', () {
      final invite = ParentInvite.fromMap({
        'id': 'i1',
        'family_id': 'f1',
        'inviter_id': 'p1',
        'invitee_email': 'test@example.com',
        'created_at': '2026-07-06T12:00:00Z',
      });
      expect(invite.isPending, isTrue);

      final accepted = ParentInvite.fromMap({
        'id': 'i2',
        'family_id': 'f1',
        'inviter_id': 'p1',
        'invitee_email': 'test@example.com',
        'status': 'accepted',
        'created_at': '2026-07-06T12:00:00Z',
      });
      expect(accepted.isAccepted, isTrue);
    });
  });
}
