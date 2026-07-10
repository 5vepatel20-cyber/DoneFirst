// Tests for the URL-expiry warning logic in proof_image_viewer.
// We replicate the computation here because the viewer itself is a
// StatefulWidget and we only want to test the pure branch logic.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

const Duration _signedUrlLifetime = Duration(days: 7);
const Duration _expiryWarnWindow = Duration(days: 2);

({String text, Color color, IconData icon})? computeExpiryWarning(
  DateTime? createdAt, {
  DateTime? now,
}) {
  if (createdAt == null) return null;
  final expiresAt = createdAt.add(_signedUrlLifetime);
  final remaining = expiresAt.difference(now ?? DateTime.now());
  if (remaining <= Duration.zero) {
    return (
      text: 'Photo URL expired',
      color: const Color(0xFFE74C3C),
      icon: Icons.error_outline,
    );
  }
  if (remaining <= _expiryWarnWindow) {
    final days = remaining.inDays;
    final hours = remaining.inHours;
    final text = days >= 1
        ? 'URL expires in $days day${days == 1 ? '' : 's'}'
        : 'URL expires in $hours hr';
    return (
      text: text,
      color: const Color(0xFFF39C12),
      icon: Icons.schedule,
    );
  }
  return null;
}

void main() {
  group('computeExpiryWarning', () {
    final now = DateTime(2026, 7, 10, 12, 0, 0);

    test('null createdAt → null (no warning)', () {
      expect(computeExpiryWarning(null, now: now), isNull);
    });

    test('uploaded today → null (plenty of life left)', () {
      // 7-day URL with a 2-day warn window: any time > 2 days away
      // from expiry = no warning.
      final created = now.subtract(const Duration(hours: 4));
      expect(computeExpiryWarning(created, now: now), isNull);
    });

    test('uploaded 4 days ago → null (still 3 days of life)', () {
      final created = now.subtract(const Duration(days: 4));
      expect(computeExpiryWarning(created, now: now), isNull);
    });

    test('uploaded 5 days ago → warn with 2 days remaining', () {
      final created = now.subtract(const Duration(days: 5));
      final warning = computeExpiryWarning(created, now: now);
      expect(warning, isNotNull);
      expect(warning!.text, 'URL expires in 2 days');
    });

    test('uploaded 6 days ago → warn with 1 day remaining', () {
      final created = now.subtract(const Duration(days: 6));
      final warning = computeExpiryWarning(created, now: now);
      expect(warning!.text, 'URL expires in 1 day');
    });

    test('warn uses singular "day" for exactly 1 day remaining', () {
      // Defensive against "1 days" wording.
      final created = now.subtract(const Duration(days: 6));
      final warning = computeExpiryWarning(created, now: now);
      expect(warning!.text, isNot(contains('1 days')));
    });

    test('uploaded 6 days, 23 hours ago → still warns (within window)', () {
      final created = now.subtract(
        const Duration(days: 6, hours: 23),
      );
      final warning = computeExpiryWarning(created, now: now);
      expect(warning, isNotNull);
      expect(warning!.text, contains('URL expires in'));
    });

    test('uploaded 7 days ago → expired', () {
      final created = now.subtract(const Duration(days: 7));
      final warning = computeExpiryWarning(created, now: now);
      expect(warning!.text, 'Photo URL expired');
    });

    test('uploaded 10 days ago → expired', () {
      final created = now.subtract(const Duration(days: 10));
      final warning = computeExpiryWarning(created, now: now);
      expect(warning!.text, 'Photo URL expired');
    });

    test('exact 2-day boundary → warns (inclusive window)', () {
      // Exactly 2 days remaining = should warn, not silently OK.
      final created = now.subtract(const Duration(days: 5));
      final warning = computeExpiryWarning(created, now: now);
      expect(warning, isNotNull);
    });
  });
}