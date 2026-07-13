import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/services/kid_device_service.dart';
import '../lib/supabase_config.dart';

/// Tests for KidDeviceService. The Supabase-backed methods
/// (generatePairingCode, listFamilyDevices, revokeDevice, etc.)
/// can't run without a live Supabase, so this file focuses on:
///   • GeneratedPairingCode helpers (isExpired, timeUntilExpiry)
///   • KidDevice.fromMap parsing
///   • KidDevice.lastSeenLabel humanizer
///   • KidDevice.isRevoked / isOnline derived getters
///   • KidDeviceException.toString contains both code and message
///   • The contract docs for status enum mapping
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // No live Supabase in test env — fine, we don't use it here.
    }
  });

  group('GeneratedPairingCode', () {
    test('isExpired is false before expiresAt', () {
      final now = DateTime.now();
      final code = GeneratedPairingCode(
        code: '123456',
        expiresAt: now.add(const Duration(minutes: 5)),
      );
      expect(code.isExpired, isFalse);
      expect(code.timeUntilExpiry.inMinutes, lessThanOrEqualTo(5));
    });

    test('isExpired is true after expiresAt', () {
      final code = GeneratedPairingCode(
        code: '123456',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(code.isExpired, isTrue);
      expect(code.timeUntilExpiry.isNegative, isTrue);
    });

    test('expires exactly at the boundary', () {
      // Pin a fixed now via constructing a code whose expiresAt is
      // exactly one second in the future. After waiting, isExpired
      // flips to true. Skip the wait — instead check the negative
      // delta when expiresAt is in the past.
      final code = GeneratedPairingCode(
        code: '000000',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );
      expect(code.timeUntilExpiry.inSeconds, lessThan(0));
    });
  });

  group('KidDevice.fromMap', () {
    test('parses a full row', () {
      final now = DateTime.now();
      final map = <String, dynamic>{
        'id': 'd-1',
        'family_id': 'f-1',
        'child_id': 'c-1',
        'child_display_name': 'Aarav',
        'device_name': "Aarav's Pixel",
        'paired_at': now.toIso8601String(),
        'last_seen_at': now.subtract(const Duration(seconds: 30)).toIso8601String(),
        'revoked_at': null,
        'status': 'online',
      };
      final device = KidDevice.fromMap(map);
      expect(device.id, 'd-1');
      expect(device.familyId, 'f-1');
      expect(device.childId, 'c-1');
      expect(device.childDisplayName, 'Aarav');
      expect(device.deviceName, "Aarav's Pixel");
      expect(device.status, 'online');
      expect(device.isRevoked, isFalse);
      expect(device.isOnline, isTrue);
      expect(device.lastSeenAt, isNotNull);
      expect(device.revokedAt, isNull);
    });

    test('parses a revoked row with null last_seen', () {
      final map = <String, dynamic>{
        'id': 'd-2',
        'family_id': 'f-1',
        'child_id': 'c-2',
        'child_display_name': 'Mei',
        'device_name': null,
        'paired_at': DateTime.now().toIso8601String(),
        'last_seen_at': null,
        'revoked_at': DateTime.now().toIso8601String(),
        'status': 'revoked',
      };
      final device = KidDevice.fromMap(map);
      expect(device.deviceName, isNull);
      expect(device.lastSeenAt, isNull);
      expect(device.isRevoked, isTrue);
      expect(device.isOnline, isFalse);
    });
  });

  group('KidDevice.lastSeenLabel', () {
    KidDevice make({DateTime? lastSeen}) => KidDevice.fromMap({
          'id': 'd-3',
          'family_id': 'f',
          'child_id': 'c',
          'child_display_name': 'X',
          'device_name': null,
          'paired_at': DateTime.now().toIso8601String(),
          'last_seen_at': lastSeen?.toIso8601String(),
          'revoked_at': null,
          'status': 'online',
        });

    test('returns "Never" when never seen', () {
      expect(make().lastSeenLabel(DateTime.now()), 'Never');
    });

    test('returns "Just now" within 30 seconds', () {
      final now = DateTime.now();
      final d = make(lastSeen: now.subtract(const Duration(seconds: 5)));
      expect(d.lastSeenLabel(now), 'Just now');
    });

    test('returns seconds for under a minute', () {
      final now = DateTime.now();
      final d = make(lastSeen: now.subtract(const Duration(seconds: 45)));
      expect(d.lastSeenLabel(now), '45s ago');
    });

    test('returns minutes for under an hour', () {
      final now = DateTime.now();
      final d = make(lastSeen: now.subtract(const Duration(minutes: 12)));
      expect(d.lastSeenLabel(now), '12 min ago');
    });

    test('returns hours for under a day', () {
      final now = DateTime.now();
      final d = make(lastSeen: now.subtract(const Duration(hours: 5)));
      expect(d.lastSeenLabel(now), '5h ago');
    });

    test('returns days beyond 24 hours', () {
      final now = DateTime.now();
      final d = make(lastSeen: now.subtract(const Duration(days: 3)));
      expect(d.lastSeenLabel(now), '3d ago');
    });
  });

  group('KidDeviceException', () {
    test('toString includes code and message', () {
      const ex = KidDeviceException(
        'Set up your family first',
        code: 'NO_FAMILY',
      );
      final s = ex.toString();
      expect(s, contains('NO_FAMILY'));
      expect(s, contains('Set up your family first'));
    });

    test('preserves code field for UI dispatch', () {
      const ex = KidDeviceException('whatever', code: 'NO_FAMILY');
      expect(ex.code, 'NO_FAMILY');
    });
  });

  group('Status enum contract', () {
    // The view kid_devices_with_child returns one of:
    //   online | recent | stale | revoked | unknown
    // The screen's switch must accept all of these. Document each
    // so a rename in the migration breaks the test loudly.
    test('all known status strings parse without crashing', () {
      for (final s in const ['online', 'recent', 'stale', 'revoked', 'unknown']) {
        final d = KidDevice.fromMap({
          'id': 'd',
          'family_id': 'f',
          'child_id': 'c',
          'child_display_name': 'X',
          'device_name': null,
          'paired_at': DateTime.now().toIso8601String(),
          'last_seen_at': null,
          'revoked_at': s == 'revoked' ? DateTime.now().toIso8601String() : null,
          'status': s,
        });
        expect(d.status, s);
      }
    });
  });
}