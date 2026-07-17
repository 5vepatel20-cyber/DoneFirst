import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/kiosk_service.dart';

/// Tests for KioskService against the in-memory MethodChannel
/// harness. Real native-side behaviour (lock-task, isDeviceOwner)
/// is exercised manually via SETUP.md; these tests cover the Dart
/// wrapper's null/error paths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('donefirst/kiosk');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('KioskService', () {
    test('refreshDeviceOwner returns true when native says yes', () async {
      String? lastMethod;
      messenger.setMockMethodCallHandler(channel, (call) async {
        lastMethod = call.method;
        return true;
      });
      final service = KioskService();
      await service.refreshDeviceOwner();
      expect(lastMethod, 'isDeviceOwner');
      expect(service.isDeviceOwner, isTrue);
    });

    test('refreshDeviceOwner returns false when native says no', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      final service = KioskService();
      await service.refreshDeviceOwner();
      expect(service.isDeviceOwner, isFalse);
    });

    test('refreshDeviceOwner swallows MissingPluginException on web', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw MissingPluginException('not on android');
      });
      final service = KioskService();
      await service.refreshDeviceOwner();
      expect(service.isDeviceOwner, isFalse);
    });

    test('refreshDeviceOwner swallows PlatformException', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'BOOM');
      });
      final service = KioskService();
      await service.refreshDeviceOwner();
      expect(service.isDeviceOwner, isFalse);
    });

    test('startLockTask returns true and flips isLocked', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'startLockTask') return true;
        return null;
      });
      final service = KioskService();
      expect(await service.startLockTask(), isTrue);
      expect(service.isLocked, isTrue);
    });

    test('startLockTask returns false when native refuses', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'startLockTask') return false;
        return null;
      });
      final service = KioskService();
      expect(await service.startLockTask(), isFalse);
      expect(service.isLocked, isFalse);
    });

    test('stopLockTask clears isLocked', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return call.method == 'startLockTask' ? true : null;
      });
      final service = KioskService();
      await service.startLockTask();
      expect(service.isLocked, isTrue);
      await service.stopLockTask();
      expect(service.isLocked, isFalse);
    });

    test('startLockTask returns false on MissingPluginException', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw MissingPluginException('not on android');
      });
      final service = KioskService();
      expect(await service.startLockTask(), isFalse);
    });
  });
}
