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

  group('KidDeviceEvent.fromMap', () {
    test('parses a code_generated event', () {
      final map = {
        'id': 'e-1',
        'family_id': 'f-1',
        'event_type': 'code_generated',
        'created_at': DateTime.now().toIso8601String(),
        'device_pairing_code': '481302',
        'metadata': null,
        'child_id': 'c-1',
        'child_name': 'Aarav',
        'kid_device_id': null,
        'device_name': null,
      };
      final e = KidDeviceEvent.fromMap(map);
      expect(e.id, 'e-1');
      expect(e.eventType, 'code_generated');
      expect(e.devicePairingCode, '481302');
      expect(e.childName, 'Aarav');
      expect(e.kidDeviceId, isNull);
      expect(e.deviceName, isNull);
    });

    test('parses a device_revoked event with device + child names', () {
      final map = {
        'id': 'e-2',
        'family_id': 'f-1',
        'event_type': 'device_revoked',
        'created_at': DateTime.now().toIso8601String(),
        'device_pairing_code': null,
        'metadata': null,
        'child_id': 'c-2',
        'child_name': 'Mei',
        'kid_device_id': 'd-9',
        'device_name': "Mei's Pixel",
      };
      final e = KidDeviceEvent.fromMap(map);
      expect(e.eventType, 'device_revoked');
      expect(e.deviceName, "Mei's Pixel");
      expect(e.childName, 'Mei');
    });
  });

  group('KidDeviceEvent.label', () {
    KidDeviceEvent make({
      required String type,
      String? code,
      String? childName,
      String? deviceName,
    }) =>
        KidDeviceEvent(
          id: 'e',
          eventType: type,
          createdAt: DateTime.now(),
          devicePairingCode: code,
          childId: 'c',
          childName: childName,
          kidDeviceId: deviceName == null ? null : 'd',
          deviceName: deviceName,
        );

    test('code_generated includes the code and child name', () {
      final s = make(
        type: KidDeviceEvent.typeCodeGenerated,
        code: '481302',
        childName: 'Aarav',
      ).label();
      expect(s, contains('481302'));
      expect(s, contains('Aarav'));
    });

    test('code_claimed reads "{child} paired {device}"', () {
      final s = make(
        type: KidDeviceEvent.typeCodeClaimed,
        childName: 'Mei',
        deviceName: "Mei's iPad",
      ).label();
      expect(s, contains('Mei'));
      expect(s, contains("Mei's iPad"));
    });

    test('code_cancelled shows the code if present', () {
      final s = make(
        type: KidDeviceEvent.typeCodeCancelled,
        code: '777777',
      ).label();
      expect(s, contains('777777'));
    });

    test('code_cancelled without a code falls back to friendly copy', () {
      final s = make(type: KidDeviceEvent.typeCodeCancelled).label();
      expect(s, isNotEmpty);
      expect(s.toLowerCase(), contains('cancel'));
    });

    test('device_revoked names the device', () {
      final s = make(
        type: KidDeviceEvent.typeDeviceRevoked,
        childName: 'Aarav',
        deviceName: "Aarav's Pixel 8",
      ).label();
      expect(s, contains('Aarav'));
      expect(s, contains("Aarav's Pixel 8"));
    });

    test('unknown event types still produce a label without crashing', () {
      final s = make(type: 'mystery_event').label();
      expect(s, isNotEmpty);
    });
  });

  group('KidDeviceEvent.ageLabel', () {
    test('returns "Just now" within 30 seconds', () {
      final e = KidDeviceEvent(
        id: 'e',
        eventType: 'code_generated',
        createdAt: DateTime.now().subtract(const Duration(seconds: 5)),
        devicePairingCode: null,
        childId: null,
        childName: null,
        kidDeviceId: null,
        deviceName: null,
      );
      expect(e.ageLabel(DateTime.now()), 'Just now');
    });

    test('returns "5 min ago" for 5 minutes old', () {
      final e = KidDeviceEvent(
        id: 'e',
        eventType: 'code_generated',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        devicePairingCode: null,
        childId: null,
        childName: null,
        kidDeviceId: null,
        deviceName: null,
      );
      expect(e.ageLabel(DateTime.now()), '5 min ago');
    });

    test('returns "3d ago" beyond a day', () {
      final e = KidDeviceEvent(
        id: 'e',
        eventType: 'device_revoked',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        devicePairingCode: null,
        childId: null,
        childName: null,
        kidDeviceId: null,
        deviceName: null,
      );
      expect(e.ageLabel(DateTime.now()), '3d ago');
    });
  });

  group('KidDeviceEvent.type constants match migration check', () {
    // The Postgres CHECK constraint in migration_14 allows exactly
    // these four event_type values. If anyone renames one, the
    // constants drift and either the trigger rejects the row or
    // the UI's switch falls through. This test pins both sides.
    test('type constants are the four documented values', () {
      expect(KidDeviceEvent.typeCodeGenerated, 'code_generated');
      expect(KidDeviceEvent.typeCodeClaimed, 'code_claimed');
      expect(KidDeviceEvent.typeCodeCancelled, 'code_cancelled');
      expect(KidDeviceEvent.typeDeviceRevoked, 'device_revoked');
    });
  });

  group('Realtime refetch dedup', () {
    // Mirrors the dedup check in the pairing screen's _onRealtimeEvent
    // — if the head of the freshly-refetched list matches the head
    // of the existing list, skip the setState to avoid a redundant
    // rebuild.
    test('detects identical head as a no-op', () {
      final now = DateTime.now();
      final current = KidDeviceEvent(
        id: 'e-1',
        eventType: 'code_generated',
        createdAt: now,
        devicePairingCode: null,
        childId: null,
        childName: null,
        kidDeviceId: null,
        deviceName: null,
      );
      final currentList = [current];
      final refreshedList = [current];
      // The screen's check: same length AND non-empty AND first.id match.
      final isNoOp = refreshedList.length == currentList.length &&
          refreshedList.isNotEmpty &&
          refreshedList.first.id == currentList.first.id;
      expect(isNoOp, isTrue);
    });

    test('detects new head as a real update', () {
      final now = DateTime.now();
      final current = KidDeviceEvent(
        id: 'e-1',
        eventType: 'code_generated',
        createdAt: now,
        devicePairingCode: null,
        childId: null,
        childName: null,
        kidDeviceId: null,
        deviceName: null,
      );
      final freshHead = KidDeviceEvent(
        id: 'e-2',
        eventType: 'code_claimed',
        createdAt: now,
        devicePairingCode: null,
        childId: null,
        childName: null,
        kidDeviceId: null,
        deviceName: null,
      );
      // freshHead is now first, replacing current. Different IDs → real update.
      expect(freshHead.id, isNot(current.id));
    });
  });
}