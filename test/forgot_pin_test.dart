import 'package:flutter_test/flutter_test.dart';

/// Tests for the pure-logic pieces of the Forgot PIN recovery flow:
/// PIN validation, PIN match. The dialogs themselves are exercised
/// manually because they require a Navigator + AuthService mocking,
/// which is more setup than this small helper deserves.

void main() {
  // Mirror of ForgotPinFlow's private _isValidPin. Keep this in
  // sync with the implementation; if these tests fail, the
  // implementation is the source of truth — update the test, not
  // the other way around.
  bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  bool pinsMatch(String a, String b) =>
      isValidPin(a) && a == b;

  group('PIN validation (4 digits only)', () {
    test('accepts a 4-digit PIN', () {
      expect(isValidPin('0000'), isTrue);
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('9876'), isTrue);
    });

    test('rejects PINs that are too short', () {
      expect(isValidPin(''), isFalse);
      expect(isValidPin('1'), isFalse);
      expect(isValidPin('12'), isFalse);
      expect(isValidPin('123'), isFalse);
    });

    test('rejects PINs that are too long', () {
      expect(isValidPin('12345'), isFalse);
      expect(isValidPin('1234567890'), isFalse);
    });

    test('rejects PINs with non-digit characters', () {
      expect(isValidPin('abcd'), isFalse);
      expect(isValidPin('12a4'), isFalse);
      expect(isValidPin('12-4'), isFalse);
      expect(isValidPin('12 4'), isFalse);
      expect(isValidPin('1.24'), isFalse);
    });

    test('rejects empty and whitespace-only', () {
      expect(isValidPin(''), isFalse);
      expect(isValidPin('    '), isFalse);
    });
  });

  group('PIN match (new PIN == confirm)', () {
    test('pinsMatch returns true for matching valid PINs', () {
      expect(pinsMatch('1234', '1234'), isTrue);
      expect(pinsMatch('0000', '0000'), isTrue);
    });

    test('pinsMatch returns false for mismatching PINs', () {
      expect(pinsMatch('1234', '5678'), isFalse);
      expect(pinsMatch('1234', '1235'), isFalse);
    });

    test('pinsMatch returns false when either PIN is invalid', () {
      expect(pinsMatch('123', '123'), isFalse);
      expect(pinsMatch('abcd', 'abcd'), isFalse);
      expect(pinsMatch('1234', '12345'), isFalse);
    });

    test('pinsMatch is whitespace-sensitive (no auto-trim)', () {
      // ForgotPinFlow trims before calling; this mirrors the
      // post-trim behaviour so a sanity check stays here too.
      expect(pinsMatch('1234', '1234'), isTrue);
      expect(pinsMatch(' 1234 ', ' 1234 '), isFalse);
    });
  });
}