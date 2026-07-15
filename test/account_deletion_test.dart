import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/auth_service.dart';

/// Pins the success boundary of `AuthService.deleteAccount`.
///
/// This is the line between "the user's data is actually gone on
/// the server" and "the user is still signed in but thinks their
/// data is gone" — a GDPR Article 17 (right to erasure) guarantee.
/// If anyone widens the success range (e.g. accepts 3xx redirects)
/// without thinking, this test should fail loud.
void main() {
  group('AuthService.isAccountDeletionSuccessful', () {
    test('accepts the documented 2xx success range', () {
      for (final code in [200, 201, 202, 204, 299]) {
        expect(
          AuthService.isAccountDeletionSuccessful(code),
          isTrue,
          reason: '$code should count as success',
        );
      }
    });

    test('rejects non-2xx', () {
      // Matrix covers the realistic failure modes:
      //   401 = bad/expired token
      //   405 = wrong HTTP method (defensive; the function rejects it)
      //   500 = server-side error mid-cascade
      for (final code in [199, 300, 301, 400, 401, 403, 404, 405, 500, 503]) {
        expect(
          AuthService.isAccountDeletionSuccessful(code),
          isFalse,
          reason: '$code should NOT count as success',
        );
      }
    });
  });

  group('AccountDeletionException', () {
    test('carries the server status code in the message', () {
      const e = AccountDeletionException('Server returned 500');
      expect(e.toString(), contains('500'));
      expect(e.toString(), contains('AccountDeletionException'));
    });
  });
}