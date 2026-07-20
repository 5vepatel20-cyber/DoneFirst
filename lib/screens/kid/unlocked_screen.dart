import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/homework_session.dart';
import '../../models/recurring_schedule.dart';
import '../../services/schedule_service.dart';
import '../../services/streak_service.dart';
import '../../theme/app_theme.dart';

/// The kid's home. Shown when the realtime subscription is healthy
/// and there's no active homework session.
///
/// This used to be a single centered checkmark ("All clear") — a
/// receipt, not a home. It's the screen the kid sees most, so it's
/// now a real dashboard: a time-aware greeting, this week's progress
/// ring, their streak, a week-at-a-glance strip, and today's
/// homework status. Every number is real (pulled from their own
/// sessions/schedules) and the screen degrades gracefully to a calm
/// "all caught up" state if a fetch returns nothing.
class UnlockedScreen extends StatefulWidget {
  final String childName;

  /// The kid's child_id. Null only on the brief race-fallback path
  /// in kid_root; when null we skip the data fetch and show the
  /// calm empty home rather than erroring.
  final String? childId;

  const UnlockedScreen({
    super.key,
    required this.childName,
    this.childId,
  });

  @override
  State<UnlockedScreen> createState() => _UnlockedScreenState();
}

class _UnlockedScreenState extends State<UnlockedScreen>
    with SingleTickerProviderStateMixin {
  final _streaks = StreakService();
  final _schedules = ScheduleService();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _loading = true;
  int _streak = 0;
  int _weekMinutes = 0;
  int _weekSessions = 0;
  int _weeklyGoal = 5;
  bool _doneToday = false;
  int? _todayScheduledMinutes;
  // Weekday indices (0 = Mon … 6 = Sun) that have a completed
  // session this week — drives the week-at-a-glance dots.
  Set<int> _activeDays = const {};

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    _load();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final childId = widget.childId;
    if (childId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Each fetch is independent and best-effort: if RLS or the
    // network drops one, the others still populate and the screen
    // shows whatever it could get rather than a scary error.
    final results = await Future.wait([
      _streaks.getStreakCount(childId).catchError((_) => 0),
      _streaks
          .getRecentSessions(childId, limit: 60)
          .catchError((_) => <HomeworkSession>[]),
      _schedules
          .getSchedules(childId)
          .catchError((_) => <RecurringSchedule>[]),
    ]);

    final streak = results[0] as int;
    final sessions = results[1] as List<HomeworkSession>;
    final schedules = results[2] as List<RecurringSchedule>;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: now.weekday - 1));
    final todayIndex = now.weekday - 1;

    var weekMinutes = 0;
    var weekSessions = 0;
    var doneToday = false;
    final activeDays = <int>{};

    for (final s in sessions) {
      if (!s.isCompleted) continue;
      final started = DateTime(
        s.startedAt.year,
        s.startedAt.month,
        s.startedAt.day,
      );
      if (started.isBefore(weekStart)) continue;
      final minutes = _sessionMinutes(s);
      weekMinutes += minutes;
      weekSessions += 1;
      activeDays.add(s.startedAt.weekday - 1);
      if (started == today) doneToday = true;
    }

    // Weekly goal = the number of days the kid actually has
    // homework scheduled (so a 3-day-a-week kid isn't guilted by a
    // 5-ring). Falls back to 5 when no schedule exists yet.
    final scheduledDays = schedules.map((s) => s.dayOfWeek).toSet();
    final weeklyGoal = scheduledDays.isEmpty ? 5 : scheduledDays.length;

    final todaySchedule =
        schedules.where((s) => s.dayOfWeek == todayIndex).toList();
    final todayScheduledMinutes =
        todaySchedule.isEmpty ? null : todaySchedule.first.durationMinutes;

    if (!mounted) return;
    setState(() {
      _loading = false;
      _streak = streak;
      _weekMinutes = weekMinutes;
      _weekSessions = weekSessions;
      _weeklyGoal = weeklyGoal;
      _doneToday = doneToday;
      _todayScheduledMinutes = todayScheduledMinutes;
      _activeDays = activeDays;
    });
  }

  int _sessionMinutes(HomeworkSession s) {
    final ended = s.endedAt;
    if (ended != null) {
      final m = ended.difference(s.startedAt).inMinutes;
      if (m > 0) return m;
    }
    return s.minLockMinutes;
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 21) return 'Good evening';
    return 'Winding down';
  }

  String get _dateLabel {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  // Status line under the greeting — the emotional core of the
  // screen. Contextual and *earned*, never the old always-on
  // "Nice work staying focused".
  ({IconData icon, Color tint, String title, String body}) get _status {
    if (_todayScheduledMinutes != null && !_doneToday) {
      return (
        icon: LucideIcons.bookOpen,
        tint: AppColors.grass,
        title: 'Homework today',
        body:
            '$_todayScheduledMinutes min scheduled. Your parent will '
            "start it when it's time — you're free until then.",
      );
    }
    if (_doneToday) {
      return (
        icon: LucideIcons.partyPopper,
        tint: AppColors.grass,
        title: 'Done for today',
        body: "Homework's finished — the rest of the day is yours. "
            'Nice work.',
      );
    }
    return (
      icon: LucideIcons.leaf,
      tint: AppColors.grass,
      title: "You're all caught up",
      body: 'No homework scheduled right now. Enjoy your apps — '
          "we'll let you know when it's homework time.",
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final progress =
        _weeklyGoal == 0 ? 0.0 : (_weekSessions / _weeklyGoal).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.kidBg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                24,
                AppSpacing.screenPadding,
                28,
              ),
              children: [
                _header(),
                const SizedBox(height: 22),
                _heroCard(status, progress),
                const SizedBox(height: 14),
                _weekStrip(),
                const SizedBox(height: 14),
                _streakCard(),
                const SizedBox(height: 14),
                _statsRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Greeting header ───────────────────────────────────────────
  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting,
                style: AppText.bodySecondary(size: 14),
              ),
              const SizedBox(height: 2),
              Text(
                widget.childName,
                style: AppText.title(size: 28, color: AppColors.kidInk),
              ),
              const SizedBox(height: 4),
              Text(
                _dateLabel,
                style: AppText.bodySecondary(size: 12.5),
              ),
            ],
          ),
        ),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.okFill,
            borderRadius: BorderRadius.circular(AppRadius.kidCard),
          ),
          child:
              const Icon(LucideIcons.sprout, size: 26, color: AppColors.grass),
        ),
      ],
    );
  }

  // ── Hero status card with weekly ring ─────────────────────────
  Widget _heroCard(
    ({IconData icon, Color tint, String title, String body}) status,
    double progress,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _WeekRing(
            progress: progress,
            done: _weekSessions,
            goal: _weeklyGoal,
            loading: _loading,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(status.icon, size: 18, color: status.tint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status.title,
                        style: AppText.cardHeader(
                            size: 17, color: AppColors.kidInk),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  status.body,
                  style: AppText.bodySecondary(size: 13).copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Week at a glance: 7 day dots ──────────────────────────────
  Widget _weekStrip() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final todayIndex = DateTime.now().weekday - 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: AppText.eyebrow()),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final active = _activeDays.contains(i);
              final isToday = i == todayIndex;
              return Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: active ? AppColors.grass : AppColors.kidBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isToday && !active
                            ? AppColors.grass
                            : AppColors.kidLine,
                        width: isToday ? 1.6 : 1,
                      ),
                    ),
                    child: active
                        ? const Icon(LucideIcons.check,
                            size: 15, color: AppColors.card)
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: AppText.bodySecondary(
                      size: 11,
                      color: isToday ? AppColors.grass : AppColors.muted,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Streak card ───────────────────────────────────────────────
  Widget _streakCard() {
    final on = _streak > 0;
    final String nudge;
    if (!on) {
      nudge = 'Finish a homework session to start a streak.';
    } else if (_doneToday) {
      nudge = 'You kept it alive today — keep the fire going.';
    } else {
      nudge = "Do today's homework to keep your streak alive.";
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: on ? AppColors.warnFill : AppColors.kidBg,
              borderRadius: BorderRadius.circular(AppRadius.iconTile + 4),
            ),
            child: Icon(
              LucideIcons.flame,
              size: 24,
              color: on ? AppColors.warnDot : AppColors.faint,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  on
                      ? (_streak == 1 ? '1-day streak' : '$_streak-day streak')
                      : 'No streak yet',
                  style: AppText.cardHeader(size: 16, color: AppColors.kidInk),
                ),
                const SizedBox(height: 3),
                Text(nudge, style: AppText.bodySecondary(size: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stat pills row ────────────────────────────────────────────
  Widget _statsRow() {
    return Row(
      children: [
        Expanded(
          child: _statTile(
            icon: LucideIcons.timer,
            value: _formatMinutes(_weekMinutes),
            label: 'This week',
            tint: AppColors.grass,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statTile(
            icon: LucideIcons.circleCheckBig,
            value: '$_weekSessions',
            label: _weekSessions == 1 ? 'Session' : 'Sessions',
            tint: AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _statTile({
    required IconData icon,
    required String value,
    required String label,
    required Color tint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: AppText.statValue(color: AppColors.kidInk)
                      .copyWith(fontSize: 18)),
              const SizedBox(height: 1),
              Text(label, style: AppText.bodySecondary(size: 11.5)),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.kidCard),
        border: Border.all(color: AppColors.kidLine),
        boxShadow: [
          BoxShadow(
            color: AppColors.forest.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      );

  static String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

/// Compact circular progress ring for "sessions this week vs goal".
/// Animates its arc from 0 → progress on load via TweenAnimationBuilder
/// so the ring "fills" when the real data arrives.
class _WeekRing extends StatelessWidget {
  final double progress;
  final int done;
  final int goal;
  final bool loading;

  const _WeekRing({
    required this.progress,
    required this.done,
    required this.goal,
    required this.loading,
  });

  static const double _size = 86;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, value, _) => CustomPaint(
          painter: _WeekRingPainter(value),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  loading ? '—' : '$done/$goal',
                  style: AppText.statValue(color: AppColors.kidInk).copyWith(fontSize: 20),
                ),
                Text('done', style: AppText.bodySecondary(size: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekRingPainter extends CustomPainter {
  final double progress;
  _WeekRingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 5;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = AppColors.kidLine;
    canvas.drawCircle(center, radius, track);

    if (progress > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = AppColors.grass;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        progress * 2 * pi,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeekRingPainter old) =>
      old.progress != progress;
}
