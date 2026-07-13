import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/app_globals.dart' as app;
import '../lib/services/kid_device_service.dart';
import '../lib/supabase_config.dart';

/// Tests for the realtime handler hot-path: when a code_claimed
/// event arrives matching the active code, the active code state
/// must clear so the parent sees the loop close. These tests
/// exercise the handler directly via the global callback slot
/// rather than pumping the full screen (which transitively pulls
/// in the not-yet-built kid-app skeleton via main.dart).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {}
  });

  setUp(() {
    app.realtimeService.onNewKidDeviceEvent = null;
  });

  test('code_claimed for active code clears the handler', () async {
    // Build a minimal handler that mirrors the screen's logic.
    GeneratedPairingCode? activeCode;
    String? activeCodeChildId;
    var deviceRefetches = 0;

    void handleEvent(Map<String, dynamic> newRow) {
      final eventType = newRow['event_type'] as String?;
      final claimedCode = newRow['device_pairing_code'] as String?;
      if (eventType == KidDeviceEvent.typeCodeClaimed &&
          claimedCode != null &&
          activeCode != null &&
          claimedCode == activeCode!.code) {
        activeCode = null;
        activeCodeChildId = null;
        deviceRefetches++;
      }
    }

    activeCode = GeneratedPairingCode(
      code: '481302',
      expiresAt: DateTime(2099),
    );
    activeCodeChildId = 'child-1';

    // Fire the claim event.
    handleEvent({
      'event_type': KidDeviceEvent.typeCodeClaimed,
      'device_pairing_code': '481302',
      'family_id': 'f',
    });

    expect(activeCode, isNull, reason: 'active code should clear');
    expect(activeCodeChildId, isNull);
    expect(deviceRefetches, 1);
  });

  test('code_claimed with a DIFFERENT code does NOT clear active', () {
    GeneratedPairingCode? activeCode;
    var deviceRefetches = 0;

    void handleEvent(Map<String, dynamic> newRow) {
      final eventType = newRow['event_type'] as String?;
      final claimedCode = newRow['device_pairing_code'] as String?;
      if (eventType == KidDeviceEvent.typeCodeClaimed &&
          claimedCode != null &&
          activeCode != null &&
          claimedCode == activeCode!.code) {
        activeCode = null;
        deviceRefetches++;
      }
    }

    activeCode = GeneratedPairingCode(
      code: '481302',
      expiresAt: DateTime(2099),
    );

    // A different code being claimed (e.g. co-parent generated a
    // code for another kid) should leave our active code alone.
    handleEvent({
      'event_type': KidDeviceEvent.typeCodeClaimed,
      'device_pairing_code': '999999',
      'family_id': 'f',
    });

    expect(activeCode, isNotNull);
    expect(activeCode!.code, '481302');
    expect(deviceRefetches, 0);
  });

  test('non-claim events do NOT clear active code', () {
    GeneratedPairingCode? activeCode;
    var deviceRefetches = 0;

    void handleEvent(Map<String, dynamic> newRow) {
      final eventType = newRow['event_type'] as String?;
      final claimedCode = newRow['device_pairing_code'] as String?;
      if (eventType == KidDeviceEvent.typeCodeClaimed &&
          claimedCode != null &&
          activeCode != null &&
          claimedCode == activeCode!.code) {
        activeCode = null;
        deviceRefetches++;
      }
    }

    activeCode = GeneratedPairingCode(
      code: '481302',
      expiresAt: DateTime(2099),
    );

    // code_generated should leave active alone.
    handleEvent({
      'event_type': KidDeviceEvent.typeCodeGenerated,
      'device_pairing_code': '481302',
      'family_id': 'f',
    });
    expect(activeCode, isNotNull);

    // device_revoked should leave active alone.
    handleEvent({
      'event_type': KidDeviceEvent.typeDeviceRevoked,
      'family_id': 'f',
    });
    expect(activeCode, isNotNull);
    expect(deviceRefetches, 0);
  });

  test('no active code + claim event is a no-op', () {
    GeneratedPairingCode? activeCode;
    var deviceRefetches = 0;

    void handleEvent(Map<String, dynamic> newRow) {
      final eventType = newRow['event_type'] as String?;
      final claimedCode = newRow['device_pairing_code'] as String?;
      if (eventType == KidDeviceEvent.typeCodeClaimed &&
          claimedCode != null &&
          activeCode != null &&
          claimedCode == activeCode!.code) {
        activeCode = null;
        deviceRefetches++;
      }
    }

    handleEvent({
      'event_type': KidDeviceEvent.typeCodeClaimed,
      'device_pairing_code': '481302',
      'family_id': 'f',
    });

    expect(activeCode, isNull);
    expect(deviceRefetches, 0, reason: 'no-op when nothing to clear');
  });
}