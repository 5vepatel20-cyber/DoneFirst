import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('returns null for valid email', () {
      expect(Validators.email('test@example.com'), isNull);
      expect(Validators.email('user@co.uk'), isNull);
    });

    test('returns error for empty', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email(null), isNotNull);
    });

    test('returns error for invalid', () {
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('@domain.com'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('returns null for valid password', () {
      expect(Validators.password('abcdef'), isNull);
      expect(Validators.password('123456'), isNull);
    });

    test('returns error for too short', () {
      expect(Validators.password('abc'), isNotNull);
    });

    test('returns error for empty', () {
      expect(Validators.password(''), isNotNull);
      expect(Validators.password(null), isNotNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('returns null when passwords match', () {
      expect(Validators.confirmPassword('abc123', 'abc123'), isNull);
    });

    test('returns error when they differ', () {
      expect(Validators.confirmPassword('abc123', 'different'), isNotNull);
    });
  });

  group('Validators.name', () {
    test('returns null for valid name', () {
      expect(Validators.name('Alice'), isNull);
    });

    test('returns error for short name', () {
      expect(Validators.name('A'), isNotNull);
    });
  });

  group('Validators.pin', () {
    test('returns null for 4-digit pin', () {
      expect(Validators.pin('1234'), isNull);
    });

    test('returns error for non-digit', () {
      expect(Validators.pin('12a4'), isNotNull);
    });

    test('returns error for wrong length', () => expect(Validators.pin('123'), isNotNull));
  });
}
