// Tests for the canonical subjects list + normalizeSubject fallback.
import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/utils/subjects.dart';

void main() {
  test('default subject is the first entry', () {
    expect(kSubjects.first, kDefaultSubject);
  });

  test('subjects list is non-empty and contains the default', () {
    expect(kSubjects, contains(kDefaultSubject));
    expect(kSubjects.length, greaterThan(3));
  });

  test('subjects are unique', () {
    expect(kSubjects.toSet().length, kSubjects.length);
  });

  test('normalizeSubject returns input for known values', () {
    expect(normalizeSubject('Math'), 'Math');
    expect(normalizeSubject('General'), 'General');
  });

  test('normalizeSubject falls back to default for unknown values', () {
    // Older DB rows might have a subject we removed. Don't crash —
    // just fall back to the default so the UI never says "null".
    expect(normalizeSubject(null), kDefaultSubject);
    expect(normalizeSubject('Astrology'), kDefaultSubject);
    expect(normalizeSubject(''), kDefaultSubject);
  });
}