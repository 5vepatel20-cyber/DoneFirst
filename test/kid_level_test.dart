import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/utils/kid_level.dart';

/// The Progress tab and the Me tab both render a level, a title and
/// "N XP to Level M". They used to be free to disagree — this pins the
/// single source they now share.
void main() {
  test('a kid with no completed sessions is Level 1, not Level 0', () {
    const l = KidLevel(0);
    expect(l.totalXp, 0);
    expect(l.level, 1);
    expect(l.xpIntoLevel, 0);
    expect(l.xpToNext, KidLevel.xpPerLevel);
    expect(l.progress, 0);
    expect(l.title, 'Focus Explorer');
  });

  test('levels advance every 500 XP / 5 completed sessions', () {
    expect(const KidLevel(4).level, 1, reason: '400 XP is still Level 1');
    expect(const KidLevel(5).level, 2, reason: '500 XP rolls over');
    expect(const KidLevel(9).level, 2);
    expect(const KidLevel(10).level, 3);
  });

  test('xpToNext never reads as zero at a level boundary', () {
    // A kid who has *just* levelled up is at the start of the new
    // level, so the gap to the next one is a full level — never 0,
    // which would render "0 XP to Level 3" on a fresh Level 2.
    const justLevelled = KidLevel(5);
    expect(justLevelled.xpIntoLevel, 0);
    expect(justLevelled.xpToNext, KidLevel.xpPerLevel);
    expect(justLevelled.level, 2);
  });

  test('progress stays within 0..1 across a level', () {
    for (var sessions = 0; sessions <= 40; sessions++) {
      final p = KidLevel(sessions).progress;
      expect(p, greaterThanOrEqualTo(0));
      expect(p, lessThan(1));
    }
  });

  test('titles match the redesign ladder: Explorer, Pro at 5, Master at 8', () {
    expect(KidLevel.titleFor(1), 'Focus Explorer');
    expect(KidLevel.titleFor(4), 'Focus Explorer');
    expect(KidLevel.titleFor(5), 'Focus Pro');
    expect(KidLevel.titleFor(7), 'Focus Pro');
    expect(KidLevel.titleFor(8), 'Focus Master');
    expect(KidLevel.titleFor(99), 'Focus Master');
  });
}
