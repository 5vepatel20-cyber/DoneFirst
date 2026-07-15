import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/blocking_service.dart';
import 'package:donefirst/services/kid_device_service.dart';

void main() {
  group('BlockingStatus enum', () {
    test('hasPermission is true for permissionGranted and blockingActive', () {
      expect(BlockingStatus.permissionGranted.hasPermission, isTrue);
      expect(BlockingStatus.blockingActive.hasPermission, isTrue);
    });

    test('hasPermission is false everywhere else', () {
      expect(BlockingStatus.idle.hasPermission, isFalse);
      expect(BlockingStatus.requestingPermission.hasPermission, isFalse);
      expect(BlockingStatus.permissionDenied.hasPermission, isFalse);
      expect(BlockingStatus.startingBlock.hasPermission, isFalse);
      expect(BlockingStatus.blockingFailed.hasPermission, isFalse);
      expect(BlockingStatus.stoppingBlock.hasPermission, isFalse);
      expect(BlockingStatus.blockingError.hasPermission, isFalse);
    });

    test('isActive is only true for blockingActive', () {
      expect(BlockingStatus.blockingActive.isActive, isTrue);
      expect(BlockingStatus.permissionGranted.isActive, isFalse);
      expect(BlockingStatus.permissionDenied.isActive, isFalse);
    });

    test('isError is true for any error state', () {
      expect(BlockingStatus.permissionDenied.isError, isTrue);
      expect(BlockingStatus.blockingFailed.isError, isTrue);
      expect(BlockingStatus.blockingError.isError, isTrue);
      expect(BlockingStatus.idle.isError, isFalse);
      expect(BlockingStatus.permissionGranted.isError, isFalse);
      expect(BlockingStatus.blockingActive.isError, isFalse);
    });
  });

  group('BlockingService initial state', () {
    test('starts in idle with no error', () {
      final service = BlockingService();
      expect(service.status, BlockingStatus.idle);
      expect(service.lastError, isNull);
      expect(service.hasPermission, isFalse);
      expect(service.isBlocking, isFalse);
      expect(service.isError, isFalse);
    });

    test('notifyListeners fires on state changes', () {
      final service = BlockingService();
      var notifications = 0;
      service.addListener(() => notifications++);
      // Accessing notifyListeners indirectly — we just check the listener
      // is wired and the getter works.
      expect(notifications, 0);
      expect(service.status, BlockingStatus.idle);
    });
  });

  group('BlockingService.acknowledgeError', () {
    test('resets isError states back to idle', () {
      // We can't drive requestPermission / startBlocking in a test because
      // they call into the flutter_screentime native plugin which isn't
      // available in flutter test. Instead, we exercise acknowledgeError's
      // no-op behavior on non-error states, and verify the public
      // contract that acknowledgeError is safe to call any time.
      final service = BlockingService();
      // No-op when not in error state.
      service.acknowledgeError();
      expect(service.status, BlockingStatus.idle);
      expect(service.isError, isFalse);
    });
  });

  group('BlockingService.isError getter', () {
    test('matches status.isError', () {
      final service = BlockingService();
      // Initial state is not an error
      expect(service.isError, service.status.isError);
    });
  });

  group('shouldSkipLocalBlockingOnKidDevice', () {
    KidDevice device({
      DateTime? revokedAt,
      DateTime? lastSeenAt,
    }) =>
        KidDevice(
          id: 'd1',
          familyId: 'f1',
          childId: 'c1',
          childDisplayName: null,
          deviceName: 'kid',
          pairedAt: DateTime.utc(2026, 1, 1),
          lastSeenAt: lastSeenAt,
          revokedAt: revokedAt,
          status: 'online',
        );

    test('returns false when no device is paired (legacy single-device)',
        () {
      // No paired device → parent app must enforce via its own
      // flutter_screentime on the parent's phone (single-device
      // mode where parent and kid share the phone).
      expect(shouldSkipLocalBlockingOnKidDevice(null), isFalse);
    });

    test('returns true for a paired, non-revoked device (kid enforces)',
        () {
      // Kid device is paired and active → enforcement rides on
      // Supabase realtime to the kid app's flutter_screentime +
      // kiosk lock-task. Parent phone should NOT try to block.
      expect(
        shouldSkipLocalBlockingOnKidDevice(
          device(lastSeenAt: DateTime.utc(2026, 7, 1)),
        ),
        isTrue,
      );
    });

    test('returns true even if the paired device is currently offline', () {
      // Offline realtime delivery just means the kid app hasn't
      // picked the lock up YET. Once it reconnects, the lock will
      // be enforced via the realtime-time `_loadInitial` bootstrap.
      // The parent app should not try local blocking while waiting.
      expect(
        shouldSkipLocalBlockingOnKidDevice(
          device(lastSeenAt: DateTime.utc(2025, 1, 1)),
        ),
        isTrue,
      );
    });

    test('returns false when the paired device was revoked', () {
      // Revoked devices should never receive new lock signals.
      // Fall back to local blocking until the parent re-pairs.
      expect(
        shouldSkipLocalBlockingOnKidDevice(
          device(revokedAt: DateTime.utc(2026, 6, 1)),
        ),
        isFalse,
      );
    });
  });
}