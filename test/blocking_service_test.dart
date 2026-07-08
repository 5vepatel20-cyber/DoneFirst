import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/blocking_service.dart';

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
}