import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/homework_session.dart';
import '../../services/streak_service.dart';
import '../../theme/app_theme.dart';
import 'kid_settings_button.dart';

/// The kid's no-active-session screen — shown when the realtime
/// subscription is healthy and nothing is locking the device.
///
/// Reads two ways depending on [celebrate]: the "Kid · Unlocked ✦"
/// payoff after a session actually ends, or a calm "all clear" when
/// there simply isn't one. Both carry the real numbers behind the
/// moment (this week's focus, streak, sessions), pulled from the
/// kid's own sessions and held at "—" when they can't be loaded.
class UnlockedScreen extends StatefulWidget {
  final String childName;

  /// The kid's child_id. Null only on the brief race-fallback path
  /// in kid_root; when null we skip the data fetch and hold the stat
  /// tiles at "—" rather than erroring.
  final String? childId;

  /// Clears the pairing and returns to the pairing screen. Surfaced
  /// through the settings gear in the header so a paired device is
  /// no longer a dead end.
  final Future<void> Function()? onUnpair;

  /// True only when a session actually ended during this app run.
  ///
  /// Both "your parent just released you" and "there is no session
  /// and never was one" are KidLockState.unlocked, but they don't
  /// read the same to a kid: "Approved. You're free." on a device
  /// that was never locked claims a parent approved something that
  /// never happened. False renders the calm idle copy instead.
  final bool celebrate;

  /// Ends the celebration and hands the kid back to their Today
  /// dashboard. Only supplied when [celebrate] is true — the idle
  /// "All clear." rendering *is* reached from Today and has nothing
  /// to dismiss.
  final VoidCallback? onDone;

  const UnlockedScreen({
    super.key,
    required this.childName,
    this.childId,
    this.onUnpair,
    this.celebrate = false,
    this.onDone,
  });

  @override
  State<UnlockedScreen> createState() => _UnlockedScreenState();
}

class _UnlockedScreenState extends State<UnlockedScreen>
    with SingleTickerProviderStateMixin {
  final _streaks = StreakService();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _loading = true;
  int _streak = 0;
  int _weekMinutes = 0;
  int _weekSessions = 0;
  // Tracked separately from the values so a failed fetch renders as
  // "—" rather than a confident "0". Telling a kid who just finished
  // a week of sessions that they have a 0-day streak is worse than
  // admitting we couldn't load it.
  bool _streakFailed = false;
  bool _sessionsFailed = false;

  /// Set on the childId == null path, where there's nothing to query
  /// at all. Distinct from the failure flags because it isn't an
  /// error worth apologising for — it's a momentary race in kid_root.
  bool _noChildId = false;

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
      // Nothing to query — leave every tile on "—". Rendering 0m /
      // 0 / 0 here would state, in the kid's own numbers, that they
      // did no work this week.
      if (mounted) {
        setState(() {
          _loading = false;
          _noChildId = true;
        });
      }
      return;
    }

    // Both fetches are best-effort: if RLS or the network drops one,
    // the other still populates and the screen shows whatever it got
    // rather than a scary error. Which one failed is recorded so the
    // tile can show "—" instead of a made-up zero.
    var streakFailed = false;
    var sessionsFailed = false;
    final results = await Future.wait([
      _streaks.getStreakCount(childId).catchError((Object _) {
        streakFailed = true;
        return 0;
      }),
      _streaks.getRecentSessions(childId, limit: 60).catchError((Object _) {
        sessionsFailed = true;
        return <HomeworkSession>[];
      }),
    ]);

    final streak = results[0] as int;
    final sessions = results[1] as List<HomeworkSession>;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: now.weekday - 1));

    var weekMinutes = 0;
    var weekSessions = 0;

    for (final s in sessions) {
      if (!s.isCompleted) continue;
      final started = DateTime(
        s.startedAt.year,
        s.startedAt.month,
        s.startedAt.day,
      );
      if (started.isBefore(weekStart)) continue;
      weekMinutes += _sessionMinutes(s);
      weekSessions += 1;
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _streak = streak;
      _weekMinutes = weekMinutes;
      _weekSessions = weekSessions;
      _streakFailed = streakFailed;
      _sessionsFailed = sessionsFailed;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.kidGradTop, AppColors.kidGradBottom],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Column(
                children: [
                  // Settings gear (unpair) — white to sit on green.
                  if (widget.onUnpair != null)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6, top: 4),
                        child: KidSettingsButton(
                          childName: widget.childName,
                          onUnpair: widget.onUnpair!,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding,
                        8,
                        AppSpacing.screenPadding,
                        28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 12),
                          _badge(),
                          const SizedBox(height: 26),
                          for (final line in _headline)
                            Text(
                              line,
                              textAlign: TextAlign.center,
                              style: AppText.display(
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                          const SizedBox(height: 14),
                          Text(
                            _subhead,
                            textAlign: TextAlign.center,
                            style: AppText.body(
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                          const SizedBox(height: 30),
                          _statsRow(),
                          const SizedBox(height: 30),
                          _doneButton(),
                          if (widget.onDone != null) ...[
                            const SizedBox(height: 14),
                            _backToTodayButton(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Approved" is a claim about something a parent did. It only
  /// belongs on the screen when a session actually ended; otherwise
  /// the kid is simply idle and the copy says so.
  List<String> get _headline => widget.celebrate
      ? const ['Approved.', "You're free."]
      : const ['All clear.'];

  String get _subhead => widget.celebrate
      ? 'Apps are unlocked. Nice work today.'
      : 'Nothing due right now. Your apps are unlocked — when a '
            'parent starts a session, it shows up here.';

  Widget _badge() {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        // A checkmark means "approved". Idle gets the calm leaf the
        // waiting screen already uses.
        child: Icon(
          widget.celebrate ? LucideIcons.check : LucideIcons.leaf,
          size: 36,
          color: AppColors.green,
        ),
      ),
    );
  }

  // Three glassy stat tiles over the gradient.
  Widget _statsRow() {
    // A tile shows "—" while loading and when its fetch failed; only
    // a fetch that actually came back empty prints a zero.
    String value(bool failed, String Function() render) =>
        (_loading || _noChildId || failed) ? '—' : render();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _glassStat(
                value: value(
                  _sessionsFailed,
                  () => _formatMinutes(_weekMinutes),
                ),
                caption: 'focused',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _glassStat(
                value: value(_streakFailed, () => '$_streak'),
                caption: 'day streak',
                leadingIcon: LucideIcons.flame,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _glassStat(
                value: value(_sessionsFailed, () => '$_weekSessions'),
                caption: _weekSessions == 1 ? 'session' : 'sessions',
              ),
            ),
          ],
        ),
        if (!_loading && (_streakFailed || _sessionsFailed)) ...[
          const SizedBox(height: 12),
          Text(
            "Couldn't load your numbers right now — they'll be back "
            'next time.',
            textAlign: TextAlign.center,
            style: AppText.caption(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ],
    );
  }

  Widget _glassStat({
    required String value,
    required String caption,
    IconData? leadingIcon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 18, color: Colors.white),
                const SizedBox(width: 4),
              ],
              Text(
                value,
                style: AppText.statValue(size: 24, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: AppText.caption(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }

  /// Handing the kid back to their launcher is an Android-only
  /// affordance: SystemNavigator.pop() is a no-op on web, and on iOS
  /// an app can't terminate itself (Apple rejects apps that try).
  /// Offering the button there gives the kid a control that does
  /// nothing when tapped.
  bool get _canExitToLauncher =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Escape hatch out of the celebration. It also times out on its
  /// own (see KidRoot._armCelebrationTimeout), but a kid who is done
  /// admiring their streak shouldn't have to wait out a timer to
  /// reach Today.
  Widget _backToTodayButton() {
    return TextButton(
      onPressed: widget.onDone,
      child: Text(
        'Back to today',
        style: AppText.button(
          size: 14,
          color: Colors.white.withValues(alpha: 0.92),
        ),
      ),
    );
  }

  Widget _doneButton() {
    if (!_canExitToLauncher) {
      // Nothing to hand back to, so the screen ends on a statement
      // rather than a dead control.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.lockOpen, size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Your apps are unlocked — go enjoy them.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 14, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      // Apps are already unlocked here; "open my apps" hands the kid
      // back to their device launcher.
      onTap: () => SystemNavigator.pop(),
      child: Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(AppRadius.button),
          boxShadow: const [
            BoxShadow(color: Color(0xFF0E0C09), offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Done — open my apps', style: AppText.button()),
            const SizedBox(width: 8),
            const Icon(LucideIcons.arrowRight, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }

  static String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
