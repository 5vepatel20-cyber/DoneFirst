import '../models/models.dart';

class MilestoneInfo {
  final int streak;
  final String title;
  final String message;
  final String emoji;
  final bool isSignificant;

  const MilestoneInfo({
    required this.streak,
    required this.title,
    required this.message,
    required this.emoji,
    this.isSignificant = false,
  });
}

class MilestoneService {
  static const List<int> milestones = [3, 7, 14, 30, 60, 100];

  static const Map<int, MilestoneInfo> _milestoneData = {
    3: MilestoneInfo(
      streak: 3,
      title: 'Nice Start!',
      message: '3 days in a row — you\'re building a habit!',
      emoji: '💪',
    ),
    7: MilestoneInfo(
      streak: 7,
      title: 'One Week Strong!',
      message: '7-day streak! Homework is becoming routine.',
      emoji: '🔥',
      isSignificant: true,
    ),
    14: MilestoneInfo(
      streak: 14,
      title: 'Two Weeks!',
      message: '14 days of focus. You\'re unstoppable!',
      emoji: '⭐',
      isSignificant: true,
    ),
    30: MilestoneInfo(
      streak: 30,
      title: 'Monthly Champion!',
      message: '30-day streak! A whole month of homework done first!',
      emoji: '🏆',
      isSignificant: true,
    ),
    60: MilestoneInfo(
      streak: 60,
      title: 'Two Month Legend!',
      message: '60 days! You\'re a homework legend!',
      emoji: '👑',
      isSignificant: true,
    ),
    100: MilestoneInfo(
      streak: 100,
      title: 'Century Club!',
      message: '100 days! This is a lifestyle now.',
      emoji: '🌟',
      isSignificant: true,
    ),
  };

  MilestoneInfo? checkMilestone(int streak) {
    if (streak <= 0) return null;
    for (final m in milestones) {
      if (streak == m) return _milestoneData[m];
    }
    return null;
  }

  MilestoneInfo? wasMilestoneReached(int previousStreak, int currentStreak) {
    for (final m in milestones) {
      if (previousStreak < m && currentStreak >= m) {
        return _milestoneData[m];
      }
    }
    return null;
  }
}
