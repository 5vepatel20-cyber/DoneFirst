import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/utils/pin_strength.dart';

/// Unit tests for the shared parent-PIN validator. Covers the
/// acceptance/rejection matrix and the human-readable rejection
/// reasons used by both the Settings → Set PIN dialog and the
/// Forgot PIN recovery flow.
void main() {
  group('isValidParentPin', () {
    test('accepts an ordinary random-looking 4-digit PIN', () {
      expect(isValidParentPin('4827'), isTrue);
      expect(isValidParentPin('1953'), isTrue);
      expect(isValidParentPin('0273'), isTrue); // leading zero ok
    });

    test('rejects non-4-digit input', () {
      expect(isValidParentPin(''), isFalse);
      expect(isValidParentPin('1'), isFalse);
      expect(isValidParentPin('12'), isFalse);
      expect(isValidParentPin('123'), isFalse);
      expect(isValidParentPin('12345'), isFalse);
    });

    test('rejects non-numeric input', () {
      expect(isValidParentPin('abcd'), isFalse);
      expect(isValidParentPin('12a4'), isFalse);
      expect(isValidParentPin('  42'), isFalse); // leading space
    });

    test('rejects all-same digits', () {
      for (final d in ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']) {
        expect(isValidParentPin(d * 4), isFalse, reason: '$d$d$d$d should be weak');
      }
    });

    test('rejects 4-in-a-row ascending', () {
      expect(isValidParentPin('0123'), isFalse);
      expect(isValidParentPin('1234'), isFalse);
      expect(isValidParentPin('2345'), isFalse);
      expect(isValidParentPin('3456'), isFalse);
      expect(isValidParentPin('4567'), isFalse);
      expect(isValidParentPin('5678'), isFalse);
      expect(isValidParentPin('6789'), isFalse);
    });

    test('rejects 4-in-a-row descending', () {
      expect(isValidParentPin('9876'), isFalse);
      expect(isValidParentPin('8765'), isFalse);
      expect(isValidParentPin('7654'), isFalse);
      expect(isValidParentPin('6543'), isFalse);
      expect(isValidParentPin('5432'), isFalse);
      expect(isValidParentPin('4321'), isFalse);
      expect(isValidParentPin('3210'), isFalse);
    });

    test('accepts near-sequential that has a single gap', () {
      // Two-digit step with a gap is not the same as +1 each step,
      // so should be accepted (not a top-1% guess).
      expect(isValidParentPin('1357'), isTrue);
      expect(isValidParentPin('2468'), isTrue); // even ascending
      expect(isValidParentPin('7531'), isTrue); // scrambled
    });
  });

  group('pinRejectionReason', () {
    test('returns null for a valid PIN', () {
      expect(pinRejectionReason('4827'), isNull);
    });

    test('returns a length-based reason for too-short input', () {
      expect(pinRejectionReason('1'), 'PIN must be 4 digits.');
      expect(pinRejectionReason('12345'), 'PIN must be 4 digits.');
    });

    test('returns a length-based reason for non-numeric input', () {
      expect(pinRejectionReason('abcd'), 'PIN must be 4 digits.');
    });

    test('returns the weak-PIN reason for guessable patterns', () {
      expect(
        pinRejectionReason('0000'),
        'PIN too simple — avoid 0000, 1234, or four of the same digit.',
      );
      expect(
        pinRejectionReason('1111'),
        'PIN too simple — avoid 0000, 1234, or four of the same digit.',
      );
      expect(
        pinRejectionReason('1234'),
        'PIN too simple — avoid 0000, 1234, or four of the same digit.',
      );
      expect(
        pinRejectionReason('4321'),
        'PIN too simple — avoid 0000, 1234, or four of the same digit.',
      );
    });
  });
}