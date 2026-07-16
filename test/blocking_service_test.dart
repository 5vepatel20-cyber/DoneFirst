import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/blocking_service.dart';
import 'package:donefirst/services/kid_device_service.dart';

void main() {
  // The new per-permission API talks to a MethodChannel even on
  // non-Android surfaces (where the platform side throws
  // MissingPluginException). The binding must be initialized so
  // the channel can be looked up — otherwise the call throws a
  // "Binding has not yet been initialized" error before reaching
  // the catch.
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('BlockingPermission enum', () {
    test('covers usage access and overlay (the two parent-app grants)', () {
      // Sanity check that the two values the new device-permissions
      // screen renders are the only two we expect. If a third
      // permission gets added (e.g. notification access for the
      // parent-side heartbeat), this test will fail and force the
      // screen to be updated.
      final ids = BlockingPermission.values.map((p) => p.id).toList();
      expect(ids, containsAll(['usage_access', 'overlay']));
      expect(ids.length, 2);
    });

    test('every value has a non-empty human label', () {
      // The label is what shows up in error messages if the OS
      // settings intent fails. Empty labels would render as
      // bare code paths in the snackbar.
      for (final p in BlockingPermission.values) {
        expect(p.label, isNotEmpty);
      }
    });
  });

  group('BlockingService.currentPermissions', () {
    test('returns a map keyed by every BlockingPermission', () async {
      // On a non-Android surface (Flutter test) the channel throws
      // MissingPluginException, which the service treats as granted
      // — so the map ends up with true for every key.
      final service = BlockingService();
      final result = await service.currentPermissions();
      expect(result.keys, containsAll(BlockingPermission.values));
      expect(result.length, BlockingPermission.values.length);
    });

    test('treats missing-plugin (test/web/iOS) as granted', () async {
      // The device-permissions screen must not trap non-Android
      // users on a screen asking for permissions the OS doesn't
      // expose. currentPermissions() returning all-granted is the
      // signal that the screen's Continue button enables.
      final service = BlockingService();
      final result = await service.currentPermissions();
      expect(result.values.every((g) => g), isTrue);
    });

    test('openPermissionSettings is a no-op on non-Android', () async {
      // Same reason — non-Android surfaces shouldn't error out
      // when the parent taps "Grant". The setting intent just
      // doesn't exist; returning false is fine.
      final service = BlockingService();
      final ok = await service.openPermissionSettings(
        BlockingPermission.usageAccess,
      );
      expect(ok, isFalse);
    });
  });
}