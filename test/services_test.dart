import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/models/models.dart';

void main() {
  group('ProofSubmission business logic', () {
    test('isPending/isApproved/isRejected are mutually exclusive', () {
      final pending = ProofSubmission(
        id: 'p1',
        taskId: 't1',
        imageUrl: 'https://example.com/pic.jpg',
        parentDecision: 'pending',
        createdAt: DateTime.now(),
      );
      expect(pending.isPending, isTrue);
      expect(pending.isApproved, isFalse);
      expect(pending.isRejected, isFalse);

      final approved = ProofSubmission(
        id: 'p2',
        taskId: 't1',
        imageUrl: 'https://example.com/pic.jpg',
        parentDecision: 'approved',
        createdAt: DateTime.now(),
      );
      expect(approved.isPending, isFalse);
      expect(approved.isApproved, isTrue);
      expect(approved.isRejected, isFalse);

      final rejected = ProofSubmission(
        id: 'p3',
        taskId: 't1',
        imageUrl: 'https://example.com/pic.jpg',
        parentDecision: 'rejected',
        createdAt: DateTime.now(),
      );
      expect(rejected.isPending, isFalse);
      expect(rejected.isApproved, isFalse);
      expect(rejected.isRejected, isTrue);
    });

    test('hasMultiplePhotos returns true when multiple URLs', () {
      final single = ProofSubmission(
        id: 'p1',
        taskId: 't1',
        imageUrl: 'https://example.com/pic.jpg',
        createdAt: DateTime.now(),
      );
      expect(single.hasMultiplePhotos, isFalse);

      final multi = ProofSubmission(
        id: 'p2',
        taskId: 't1',
        imageUrl: 'https://example.com/pic.jpg',
        imageUrls: ['pic1.jpg', 'pic2.jpg', 'pic3.jpg'],
        createdAt: DateTime.now(),
      );
      expect(multi.hasMultiplePhotos, isTrue);
    });
  });

  group('HomeworkSession business logic', () {
    test('isActive/isPaused/isCompleted/isCancelled are correct', () {
      final active = HomeworkSession(
        id: 's1',
        childId: 'c1',
        parentId: 'p1',
        status: 'active',
        startedAt: DateTime.now(),
        minLockMinutes: 60,
      );
      expect(active.isActive, isTrue);
      expect(active.isPaused, isFalse);
      expect(active.isCompleted, isFalse);
      expect(active.isCancelled, isFalse);

      final cancelled = HomeworkSession(
        id: 's2',
        childId: 'c1',
        parentId: 'p1',
        status: 'cancelled',
        startedAt: DateTime.now(),
        minLockMinutes: 60,
      );
      expect(cancelled.isCancelled, isTrue);
    });

    test('toMap round-trips with all fields', () {
      final original = HomeworkSession(
        id: 's1',
        childId: 'c1',
        parentId: 'p1',
        status: 'active',
        startedAt: DateTime(2026, 7, 6, 12, 0, 0),
        endedAt: DateTime(2026, 7, 6, 13, 30, 0),
        minLockMinutes: 90,
        maxLiftMinutes: 180,
        approvalMode: 'strict',
      );
      final map = original.toMap();
      final restored = HomeworkSession.fromMap(map);
      expect(restored.id, original.id);
      expect(restored.childId, original.childId);
      expect(restored.parentId, original.parentId);
      expect(restored.status, original.status);
      expect(restored.minLockMinutes, original.minLockMinutes);
      expect(restored.maxLiftMinutes, original.maxLiftMinutes);
      expect(restored.approvalMode, original.approvalMode);
      expect(restored.startedAt.toIso8601String(),
          original.startedAt.toIso8601String());
      expect(restored.endedAt?.toIso8601String(),
          original.endedAt?.toIso8601String());
    });
  });

  group('AiResult', () {
    test('isApproved/isNeedsReview/isRejected', () {
      expect(const AiResult(decision: 'approved', confidence: 0.9, reason: '').isApproved, isTrue);
      expect(const AiResult(decision: 'needs_review', confidence: 0.5, reason: '').needsReview, isTrue);
      expect(const AiResult(decision: 'rejected', confidence: 0.2, reason: '').isRejected, isTrue);
    });

    test('toJson round-trips', () {
      final ai = AiResult(
        decision: 'approved',
        confidence: 0.95,
        reason: 'Valid homework',
      );
      final json = ai.toJson();
      final restored = AiResult.fromJson(json);
      expect(restored.decision, ai.decision);
      expect(restored.confidence, ai.confidence);
      expect(restored.reason, ai.reason);
    });
  });

  group('LockPreset', () {
    test('fromMap parses correctly', () {
      final preset = LockPreset.fromMap({
        'id': 'lp1',
        'parent_id': 'p1',
        'name': 'Weekday',
        'min_lock_minutes': 60,
        'max_lift_minutes': 120,
        'approval_mode': 'balanced',
        'selected_packs': ['social', 'games'],
        'created_at': '2026-07-06T12:00:00Z',
      });
      expect(preset.name, 'Weekday');
      expect(preset.minLockMinutes, 60);
      expect(preset.maxLiftMinutes, 120);
      expect(preset.selectedPacks.length, 2);
      expect(preset.selectedPacks, contains('social'));
    });
  });

  group('AppNotification', () {
    test('fromMap parses read status', () {
      final unread = AppNotification.fromMap({
        'id': 'n1',
        'parent_id': 'p1',
        'type': 'proof_submitted',
        'title': 'Proof submitted',
        'body': 'Kid submitted homework',
        'created_at': '2026-07-06T12:00:00Z',
      });
      expect(unread.read, isFalse);

      final read = AppNotification.fromMap({
        'id': 'n2',
        'parent_id': 'p1',
        'type': 'proof_submitted',
        'title': 'Proof submitted',
        'read': true,
        'created_at': '2026-07-06T12:00:00Z',
      });
      expect(read.read, isTrue);
    });
  });

  group('BreakRequest', () {
    test('status helpers', () {
      final pending = BreakRequest(
        id: 'b1',
        sessionId: 's1',
        childId: 'c1',
        status: 'pending',
        createdAt: DateTime.now(),
      );
      expect(pending.isPending, isTrue);
      expect(pending.isApproved, isFalse);

      final approved = BreakRequest(
        id: 'b2',
        sessionId: 's1',
        childId: 'c1',
        status: 'approved',
        createdAt: DateTime.now(),
      );
      expect(approved.isApproved, isTrue);
    });
  });
}
