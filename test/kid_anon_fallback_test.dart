import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/services/kid_auth_service.dart';
import 'package:donefirst/supabase_config.dart';

/// The worst kid-app failure isn't an error, it's a 200.
///
/// When `auth.currentSession` is null, supabase's AuthHttpClient signs
/// every request with the *anon* key instead. PostgREST doesn't reject
/// that — RLS just filters every kid-scoped table down to nothing and
/// answers `200 []`. Nothing throws, so every catch block in the app
/// stays quiet and the empty reads get rendered as fact: 0m focused,
/// 0 sessions, 0 streak and "nothing scheduled yet" on a device with
/// real sessions and a real schedule. Worse, KidRealtimeService reads
/// no active session and reports `unlocked`, releasing a lock that is
/// genuinely in force.
///
/// restoreSession lands in that state whenever setSession fails but
/// the persisted JWT still decodes: the kid's identity comes back, so
/// `isPaired` is true, while the client stays unauthenticated. Before
/// the token write-back (KidAuthService._authSub) that happened on
/// every cold launch after the first background refresh, because
/// Supabase rotates the refresh token and the app only ever stored
/// the pair it was handed at pairing time.
///
/// [KidAuthService.hasLiveSession] is what tells the two apart, and
/// KidRoot.build renders WaitingScreen rather than any data screen
/// when it is false.
String fakeKidJwt() {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg({'alg': 'ES256', 'typ': 'JWT'});
  final payload = seg({
    'sub': '725804b2-0121-447b-93d5-5a9666a16466',
    'exp': 1785250376, // Long expired — that is the whole point.
    'app_metadata': {
      'child_id': '5eb6d862-c496-4857-84bf-cec7832ba1d6',
      'family_id': '5ec0c6e7-0c29-484a-a463-f3dfa72b2a11',
      'device_id': '27077f48-3b7e-42ab-9492-0bb659a5f5eb',
      'kid_device': true,
    },
  });
  return '$header.$payload.signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Offline is fine — "no session" is exactly the state under test.
    }
  });

  test('a restored-but-unauthenticated kid is paired, not readable', () async {
    SharedPreferences.setMockInitialValues({
      'kid_access_token': fakeKidJwt(),
      'kid_refresh_token': 'spent-refresh-token',
      'kid_display_name': 'Ada',
    });

    final auth = KidAuthService();
    // setSession can't succeed here (expired access token, and the
    // refresh token would be rejected), so this exercises the decode
    // fallback — the same path a real device takes once its stored
    // refresh token has been rotated out from under it.
    await auth.restoreSession();

    expect(
      auth.isPaired,
      isTrue,
      reason: 'the JWT still identifies the child, so we know who they are',
    );
    expect(auth.childId, '5eb6d862-c496-4857-84bf-cec7832ba1d6');
    expect(
      auth.hasLiveSession,
      isFalse,
      reason: 'nothing we read in this state is the kid\'s own data',
    );

    auth.dispose();
  });

  test('a device with no tokens reports neither paired nor live', () async {
    SharedPreferences.setMockInitialValues({});

    final auth = KidAuthService();
    expect(await auth.restoreSession(), isFalse);
    expect(auth.isPaired, isFalse);
    expect(auth.hasLiveSession, isFalse);

    auth.dispose();
  });
}
