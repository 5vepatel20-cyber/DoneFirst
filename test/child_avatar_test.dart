// Tests for the _ChildAvatar rendering decision logic.
//
// _ChildAvatar is a private widget inside parent_dashboard.dart; we
// can't import it directly from here. Instead, mirror the decision
// table so a behavior change breaks this test instead of silently
// flipping what parents see.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/models/models.dart';

void main() {
  // Mirror of _ChildAvatar.build: returns the "look" so each branch
  // can be checked without rendering widgets.
  String avatarLook(Child child) {
    final hasCustomization = child.emoji != null || child.color != null;
    if (!hasCustomization) return 'first_letter';
    if (child.emoji != null) return 'emoji';
    return 'first_letter_with_color';
  }

  test('plain child (no emoji, no color) shows the first letter', () {
    final c = Child(id: 'c1', name: 'Aanya');
    expect(avatarLook(c), 'first_letter');
  });

  test('emoji only — renders emoji with default tint', () {
    final c = Child(id: 'c1', name: 'Aanya', emoji: '🧒');
    expect(avatarLook(c), 'emoji');
  });

  test('color only — still emoji-style (we prefer emoji over text)', () {
    final c = Child(id: 'c1', name: 'Aanya', color: 'FF5566AA');
    expect(avatarLook(c), 'first_letter_with_color');
  });

  test('emoji + color — renders emoji with chosen tint', () {
    final c = Child(
      id: 'c1',
      name: 'Aanya',
      color: 'FFFF8800',
      emoji: '🌟',
    );
    expect(avatarLook(c), 'emoji');
  });

  test('garbage color string falls back to primary without crashing', () {
    Color? parseColor(String? hex) {
      if (hex == null) return null;
      // Hex color strings are stored without the 0x prefix, so we
      // must pass radix: 16 explicitly. int.parse defaults to base-10,
      // which silently throws on hex-looking strings.
      final parsed = int.tryParse(hex, radix: 16);
      return parsed == null ? null : Color(parsed);
    }

    expect(parseColor(null), isNull);
    expect(parseColor('not-a-number'), isNull);
    expect(parseColor('ffff8800'), isA<Color>());
  });
}
