/// XP and levels — a presentational layer over completed sessions.
///
/// There is no XP column anywhere: a kid's level is derived from how
/// many sessions they have finished, so it can never disagree with
/// their history and needs no migration or backfill.
///
/// This lives in one place on purpose. The Progress tab and the Me tab
/// both show a level, a title and "N XP to Level M", and computing
/// that twice is how a screen ends up telling a kid they are Level 4
/// in one tab and Level 5 in the next.
class KidLevel {
  /// Every completed session is worth this much XP.
  static const int xpPerSession = 100;

  /// XP needed to move up one level.
  static const int xpPerLevel = 500;

  /// Number of *completed* sessions. Sessions still running don't
  /// count — the payoff should land when the work is finished.
  final int completedSessions;

  const KidLevel(this.completedSessions);

  int get totalXp => completedSessions * xpPerSession;

  /// 1-based: a kid with no sessions is Level 1, not Level 0.
  int get level => (totalXp ~/ xpPerLevel) + 1;

  int get xpIntoLevel => totalXp % xpPerLevel;

  int get xpToNext => xpPerLevel - xpIntoLevel;

  /// 0..1, for a progress bar. Always a real fraction — [xpPerLevel]
  /// is a non-zero constant, so this cannot divide by zero.
  double get progress => xpIntoLevel / xpPerLevel;

  String get title => titleFor(level);

  /// Matches the ladder in the redesign catalog: Focus Explorer at the
  /// start, Focus Pro at Level 5, Focus Master at Level 8.
  static String titleFor(int level) => level >= 8
      ? 'Focus Master'
      : level >= 5
      ? 'Focus Pro'
      : 'Focus Explorer';
}
