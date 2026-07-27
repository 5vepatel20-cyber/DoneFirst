import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/homework_session.dart';
import '../../models/recurring_schedule.dart';
import '../../services/schedule_service.dart';
import '../../services/streak_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/df_kit.dart';
import 'kid_settings_button.dart';

/// The kid's free-time home — the "Kid · Today" dashboard from the
/// premium redesign. Shown on a paired kid device when the realtime
/// subscription is healthy and nothing is locking the device *and* no
/// session just ended (that transient "you earned it" payoff is
/// [UnlockedScreen], routed on the celebrate path in kid_root).
///
/// Same warm world as the parent app — greeting, streak, today's
/// focus, the next scheduled session, and an at-a-glance row — instead
/// of a bare lock/unlock statement. Every number is the kid's own,
/// held at "—" when a fetch can't complete rather than inventing a
/// zero that would tell a kid they did no work.
class KidTodayScreen extends StatefulWidget {
  final String childName;

  /// The kid's child_id. Null only on the brief race-fallback path in
  /// kid_root; when null we skip the data fetch and greet without
  /// numbers rather than erroring.
  final String? childId;

  /// Clears the pairing and returns to the pairing screen. Surfaced
  /// through the settings gear so a paired device is not a dead end.
  final Future<void> Function()? onUnpair;

  const KidTodayScreen({
    super.key,
    required this.childName,
    this.childId,
    this.onUnpair,
  });

  @override
  State<KidTodayScreen> createState() => _KidTodayScreenState();
}

class _KidTodayScreenState extends State<KidTodayScreen> {
  final _streaks = StreakService();
  final _schedules = ScheduleService();

  bool _loading = true;
  bool _noChildId = false;

  int _streak = 0;
  int _focusedTodayMin = 0;
  int _sessionsToday = 0;

  RecurringSchedule? _next;
  // Whole days until [_next]: 0 = today, 1 = tomorrow, else weekday name.
  int _nextInDays = 0;

  // Tracked separately so a failed fetch renders "—" rather than a
  // confident "0" — telling a kid who studied all week that their
  // streak is 0 is worse than admitting we couldn't load it.
  bool _streakFailed = false;
  bool _sessionsFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final childId = widget.childId;
    if (childId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _noChildId = true;
        });
      }
      return;
    }

    var streakFailed = false;
    var sessionsFailed = false;

    // All three are best-effort and independent: one failing still
    // lets the others populate. The schedule read is allowed to fail
    // silently — a missing "next session" card is fine, a crash is not.
    final results = await Future.wait([
      _streaks.getStreakCount(childId).catchError((Object _) {
        streakFailed = true;
        return 0;
      }),
      _streaks.getRecentSessions(childId, limit: 60).catchError((Object _) {
        sessionsFailed = true;
        return <HomeworkSession>[];
      }),
      _schedules.getSchedules(childId).catchError(
        (Object _) => <RecurringSchedule>[],
      ),
    ]);

    final streak = results[0] as int;
    final sessions = results[1] as List<HomeworkSession>;
    final schedules = results[2] as List<RecurringSchedule>;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var focusedTodayMin = 0;
    var sessionsToday = 0;
    for (final s in sessions) {
      if (!s.isCompleted) continue;
      final started = DateTime(
        s.startedAt.year,
        s.startedAt.month,
        s.startedAt.day,
      );
      if (started != today) continue;
      focusedTodayMin += _sessionMinutes(s);
      sessionsToday += 1;
    }

    final picked = _pickNext(schedules);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _streak = streak;
      _focusedTodayMin = focusedTodayMin;
      _sessionsToday = sessionsToday;
      _streakFailed = streakFailed;
      _sessionsFailed = sessionsFailed;
      _next = picked?.schedule;
      _nextInDays = picked?.inDays ?? 0;
    });
  }

  /// Nearest upcoming schedule by day-of-week, wrapping past the end
  /// of the week. Schedules carry a weekday + duration but no clock
  /// time, so "when" is a day, not an hour.
  ({RecurringSchedule schedule, int inDays})? _pickNext(
    List<RecurringSchedule> schedules,
  ) {
    if (schedules.isEmpty) return null;
    final todayDow = DateTime.now().weekday - 1; // 0 = Monday
    RecurringSchedule? best;
    var bestDelta = 8;
    for (final s in schedules) {
      var delta = (s.dayOfWeek - todayDow) % 7;
      if (delta < 0) delta += 7;
      if (delta < bestDelta) {
        bestDelta = delta;
        best = s;
      }
    }
    return best == null ? null : (schedule: best, inDays: bestDelta);
  }

  int _sessionMinutes(HomeworkSession s) {
    final ended = s.endedAt;
    if (ended != null) {
      final m = ended.difference(s.startedAt).inMinutes;
      if (m > 0) return m;
    }
    return s.minLockMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onUnpair != null)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: KidSettingsButton(
                    childName: widget.childName,
                    onUnpair: widget.onUnpair!,
                    color: AppColors.ink70,
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  6,
                  AppSpacing.screenPadding,
                  28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_dateEyebrow, style: AppText.eyebrow()),
                    const SizedBox(height: 8),
                    Text(
                      'Hi, ${widget.childName}',
                      style: AppText.display(size: 32),
                    ),
                    const SizedBox(height: 14),
                    _pills(),
                    const SizedBox(height: 20),
                    _statusCard(),
                    const SizedBox(height: 22),
                    const DfSectionLabel('Next session'),
                    _nextSessionCard(),
                    const SizedBox(height: 22),
                    const DfSectionLabel('Today at a glance'),
                    _glanceCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pills() {
    final showStreak = !_loading && !_streakFailed && _streak > 0;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        const DfStatusPill('Apps open', tone: DfPillTone.success, dot: true),
        if (showStreak)
          DfStatusPill(
            '$_streak-day streak',
            tone: DfPillTone.attention,
            icon: LucideIcons.flame,
          ),
      ],
    );
  }

  Widget _statusCard() {
    final studiedToday = !_loading && !_noChildId && _focusedTodayMin > 0;
    final IconData icon = studiedToday ? LucideIcons.check : LucideIcons.leaf;
    final String title = studiedToday
        ? 'Today’s homework is done'
        : 'No session running';
    final String body = studiedToday
        ? '$_sessionsToday ${_sessionsToday == 1 ? 'session' : 'sessions'} · '
              '${_focusedTodayMin}m focused. Your apps are open.'
        : 'Your apps are open — enjoy them. When a parent starts a '
              'session, it shows up right here.';

    return DfCard(
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconTile(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardHeader()),
                const SizedBox(height: 4),
                Text(body, style: AppText.bodySecondary()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nextSessionCard() {
    final next = _next;
    if (next == null) {
      return DfCard(
        padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
        child: Row(
          children: [
            _iconTile(
              LucideIcons.calendarDays,
              bg: AppColors.border2,
              fg: AppColors.ink70,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _noChildId
                    ? 'Getting your schedule ready…'
                    : 'Nothing scheduled yet — your parent can set up a '
                          'homework routine.',
                style: AppText.bodySecondary(),
              ),
            ),
          ],
        ),
      );
    }

    final when = _nextInDays == 0
        ? 'Today'
        : _nextInDays == 1
        ? 'Tomorrow'
        : next.dayName;

    return DfCard(
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconTile(LucideIcons.bookOpen),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Homework', style: AppText.cardHeader()),
                    const SizedBox(height: 4),
                    Text(
                      '$when · ${next.durationMinutes} min',
                      style: AppText.bodySecondary(),
                    ),
                  ],
                ),
              ),
              if (_nextInDays == 0)
                const DfStatusPill('Today', tone: DfPillTone.info),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.border2),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                LucideIcons.lock,
                size: 15,
                color: AppColors.ink45,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Games, video & social pause until your work is approved.',
                  style: AppText.caption(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _glanceCard() {
    String stat(bool failed, String Function() render) =>
        (_loading || _noChildId || failed) ? '—' : render();

    return DfCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: DfStatTile(
                stat(_sessionsFailed, () => '${_focusedTodayMin}m'),
                'focused today',
                align: CrossAxisAlignment.center,
              ),
            ),
          ),
          _divider(),
          Expanded(
            child: Center(
              child: DfStatTile(
                stat(_sessionsFailed, () => '$_sessionsToday'),
                _sessionsToday == 1 ? 'session' : 'sessions',
                align: CrossAxisAlignment.center,
              ),
            ),
          ),
          _divider(),
          Expanded(
            child: Center(
              child: DfStatTile(
                stat(_streakFailed, () => '$_streak'),
                'day streak',
                valueColor: AppColors.amberDeep,
                align: CrossAxisAlignment.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 34, color: AppColors.border2);

  Widget _iconTile(IconData icon, {Color? bg, Color? fg}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg ?? AppColors.greenTint,
        borderRadius: BorderRadius.circular(AppRadius.iconTile),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: fg ?? AppColors.green, size: 22),
    );
  }

  String get _dateEyebrow {
    final now = DateTime.now();
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = days[now.weekday - 1];
    final month = months[now.month - 1];
    return '$day · $month ${now.day}';
  }
}
