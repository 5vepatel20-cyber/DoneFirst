import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/services/kid_auth_service.dart';
import 'package:donefirst/supabase_config.dart';

/// HTTP-mocked tests for KidAuthService.claimPairingCode.
///
/// The real edge function validates the code, creates a kid_devices
/// row, and returns a Supabase anon JWT. We can't easily stub
/// supabase.auth.recoverSession (it's wired into the global
/// Supabase.instance.client). Instead, we:
///   1. Mock http.Client so claimPairingCode gets the body it
///      expects on each test.
///   2. Let recoverSession's no-op-when-token-malformed behavior
///      kick in — claimPairingCode populates _childId/_familyId/
///      _deviceId from the body before recoverSession is called.
///
/// If you change KidAuthService to delay _childId lookup until
/// AFTER recoverSession, the assertions on _childId will need to
/// move to integration tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Live Supabase not needed; recoverSession is a best-effort
      // call that swallows its own failures into a logged error.
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('claimPairingCode success paths', () {
    test(
      '200 success persists tokens and populates child/family/device',
      () async {
        final mock = MockClient((request) async {
          expect(request.url.path, contains('/functions/v1/claim-pairing'));
          expect(request.method, 'POST');
          return http.Response(
            jsonEncode({
              'success': true,
              // Properly-formed JWTs (header.payload.signature) with
              // a JSON-decodable payload. recoverSession in
              // supabase_flutter parses these and gets past the
              // JsonCodec.decode check.
              'access_token':
                  'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.signature',
              'refresh_token': 'v1.refresh',
              'child_id': 'c-mock-1',
              'family_id': 'f-mock-1',
              'device_id': 'd-mock-1',
            }),
            200,
          );
        });
        final svc = KidAuthService.withDeps(httpClient: mock);
        await svc.claimPairingCode('123456', deviceName: 'Sammy phone');

        expect(svc.childId, 'c-mock-1');
        expect(svc.familyId, 'f-mock-1');
        expect(svc.deviceId, 'd-mock-1');

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('kid_access_token'),
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.signature',
        );
        expect(prefs.getString('kid_refresh_token'), 'v1.refresh');
      },
    );

    test('omits device_name when null/empty', () async {
      String? sentBody;
      final mock = MockClient((request) async {
        sentBody = request.body;
        return http.Response(
          jsonEncode({
            'success': true,
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.s',
            'refresh_token': 'r',
            'child_id': 'c',
            'family_id': 'f',
            'device_id': 'd',
          }),
          200,
        );
      });
      final svc = KidAuthService.withDeps(httpClient: mock);
      await svc.claimPairingCode('654321');

      final parsed = jsonDecode(sentBody!) as Map<String, dynamic>;
      expect(parsed['code'], '654321');
      expect(
        parsed.containsKey('device_name'),
        isFalse,
        reason: 'device_name absent when not provided',
      );
    });

    test('includes device_name when non-empty', () async {
      String? sentBody;
      final mock = MockClient((request) async {
        sentBody = request.body;
        return http.Response(
          jsonEncode({
            'success': true,
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.s',
            'refresh_token': 'r',
            'child_id': 'c',
            'family_id': 'f',
            'device_id': 'd',
          }),
          200,
        );
      });
      final svc = KidAuthService.withDeps(httpClient: mock);
      await svc.claimPairingCode('111111', deviceName: 'Sammy phone');

      final parsed = jsonDecode(sentBody!) as Map<String, dynamic>;
      expect(parsed['device_name'], 'Sammy phone');
    });

    test('whitespace-only device_name is dropped (not sent)', () async {
      // A parent who tapped space twice by accident shouldn't end
      // up with a device whose dashboard label reads "  ". The
      // service trims and treats whitespace-only as empty, so
      // device_name is omitted from the body entirely.
      String? sentBody;
      final mock = MockClient((request) async {
        sentBody = request.body;
        return http.Response(
          jsonEncode({
            'success': true,
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.s',
            'refresh_token': 'r',
            'child_id': 'c',
            'family_id': 'f',
            'device_id': 'd',
          }),
          200,
        );
      });
      final svc = KidAuthService.withDeps(httpClient: mock);
      await svc.claimPairingCode('222222', deviceName: '  ');

      final parsed = jsonDecode(sentBody!) as Map<String, dynamic>;
      expect(
        parsed.containsKey('device_name'),
        isFalse,
        reason: 'whitespace-only names are trimmed to empty and dropped',
      );
    });

    test('leading/trailing whitespace is trimmed from device_name', () async {
      // "  Sammy phone  " → "Sammy phone". Without this the device
      // row in the dashboard would show the padding in the avatar
      // tooltip and the rename dialog.
      String? sentBody;
      final mock = MockClient((request) async {
        sentBody = request.body;
        return http.Response(
          jsonEncode({
            'success': true,
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.s',
            'refresh_token': 'r',
            'child_id': 'c',
            'family_id': 'f',
            'device_id': 'd',
          }),
          200,
        );
      });
      final svc = KidAuthService.withDeps(httpClient: mock);
      await svc.claimPairingCode('222222', deviceName: '  Sammy phone  ');

      final parsed = jsonDecode(sentBody!) as Map<String, dynamic>;
      expect(parsed['device_name'], 'Sammy phone');
    });
  });

  group('claimPairingCode error mappings', () {
    test('410 → KidAuthException with EXPIRED', () async {
      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({'success': false, 'error': 'Code expired'}),
          410,
        ),
      );
      final svc = KidAuthService.withDeps(httpClient: mock);
      expect(
        () => svc.claimPairingCode('999999'),
        throwsA(predicate((e) => e is KidAuthException && e.code == 'EXPIRED')),
      );
    });

    test('400 with valid JSON error body → BAD_CODE', () async {
      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({'success': false, 'error': 'Bad code format'}),
          400,
        ),
      );
      final svc = KidAuthService.withDeps(httpClient: mock);
      expect(
        () => svc.claimPairingCode('12'),
        throwsA(
          predicate((e) => e is KidAuthException && e.code == 'BAD_CODE'),
        ),
      );
    });

    test('400 with empty body → fallback BAD_CODE message', () async {
      final mock = MockClient((request) async => http.Response('', 400));
      final svc = KidAuthService.withDeps(httpClient: mock);
      expect(
        () => svc.claimPairingCode('12'),
        throwsA(
          predicate(
            (e) =>
                e is KidAuthException &&
                e.code == 'BAD_CODE' &&
                e.message == 'Code must be 6 digits',
          ),
        ),
      );
    });

    test('500 → SERVER_ERROR', () async {
      final mock = MockClient(
        (request) async => http.Response('Internal Server Error', 500),
      );
      final svc = KidAuthService.withDeps(httpClient: mock);
      expect(
        () => svc.claimPairingCode('123456'),
        throwsA(
          predicate((e) => e is KidAuthException && e.code == 'SERVER_ERROR'),
        ),
      );
    });

    test('200 with success=false → SERVER_ERROR with body error', () async {
      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({'success': false, 'error': 'rate-limited'}),
          200,
        ),
      );
      final svc = KidAuthService.withDeps(httpClient: mock);
      expect(
        () => svc.claimPairingCode('123456'),
        throwsA(
          predicate(
            (e) =>
                e is KidAuthException &&
                e.code == 'SERVER_ERROR' &&
                e.message == 'rate-limited',
          ),
        ),
      );
    });

    test('200 with success=false and no error → generic message', () async {
      final mock = MockClient(
        (request) async => http.Response(jsonEncode({'success': false}), 200),
      );
      final svc = KidAuthService.withDeps(httpClient: mock);
      expect(
        () => svc.claimPairingCode('123456'),
        throwsA(
          predicate(
            (e) =>
                e is KidAuthException &&
                e.code == 'SERVER_ERROR' &&
                e.message == 'Pairing failed',
          ),
        ),
      );
    });

    test('200 with success=true but no tokens → BAD_RESPONSE', () async {
      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'success': true,
            'child_id': 'c',
            'family_id': 'f',
            'device_id': 'd',
            // missing access_token + refresh_token
          }),
          200,
        ),
      );
      final svc = KidAuthService.withDeps(httpClient: mock);
      expect(
        () => svc.claimPairingCode('123456'),
        throwsA(
          predicate((e) => e is KidAuthException && e.code == 'BAD_RESPONSE'),
        ),
      );
    });

    test('200 with malformed JSON body → SERVER_ERROR', () async {
      final mock = MockClient(
        (request) async => http.Response('not json', 200),
      );
      final svc = KidAuthService.withDeps(httpClient: mock);
      expect(
        () => svc.claimPairingCode('123456'),
        throwsA(
          predicate((e) => e is KidAuthException && e.code == 'SERVER_ERROR'),
        ),
      );
    });
  });

  group('KidAuthException semantics', () {
    test('toString includes both code and message', () {
      const ex = KidAuthException('m', code: 'C');
      expect(ex.toString(), contains('C'));
      expect(ex.toString(), contains('m'));
    });

    test('is an Exception subclass', () {
      expect(const KidAuthException('m', code: 'C'), isA<Exception>());
    });
  });
}
