import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/homework_session.dart';
import '../../services/streak_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/kid_level.dart';
import '../../widgets/df_kit.dart';
import '../../widgets/shimmer_loading.dart';

/// The "Kid · Me" tab: a little identity — level, streak, and a couple
/// of kid-safe toggles.
///
/// WHY THIS ISN'T KidProfileScreen
///
/// The redesign's Me screen already had an implementation
/// (`kid_profile_screen.dart`), but it cannot be handed to a kid for
/// two independent reasons:
///
///   1. It takes a full `Child` model, and kids have **no SELECT
///      policy on `children`**. A kid's JWT reading that table doesn't
///      get an error, it gets `200 []` — so the screen would render
///      blank fields rather than fail, which is the same silent-empty
///      trap that made the kid app show 0m focused for a week of work.
///   2. It is a parent's editor: it renames the child, rewrites their
///      profile, and can *delete the child entirely*. None of that
///      belongs on the child's own device.
///
/// So this screen derives everything from tables the kid can actually
/// read — `homework_sessions` via StreakService — and keeps its two
/// preferences on the device.
class KidMeScreen extends StatefulWidget {
  final String childId;
  final String childName;

  /// Clears the pairing. Null hides the unpair row (the shell's gear
  /// still offers it wherever it is shown).
  final Future<void> Function()? onUnpair;

  const KidMeScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.onUnpair,
  });

  @override
  State<KidMeScreen> createState() => _KidMeScreenState();
}

class _KidMeScreenState extends State<KidMeScreen> {
  static const String _kSounds = 'kid_sounds_enabled';

  final _streaks = StreakService();

  bool _loading = true;
  bool _failed = false;
  int _streak = 0;
  List<HomeworkSession> _sessions = const [];
  bool _sounds = true;

  static const Duration _readTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _load();
    _restorePrefs();
  }

  @override
  void didUpdateWidget(KidMeScreen old) {
    super.didUpdateWidget(old);
    if (widget.childId != old.childId) _load();
  }

  Future<void> _restorePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _sounds = prefs.getBool(_kSounds) ?? true);
    } catch (_) {
      // A prefs failure shouldn't cost the kid the whole screen; the
      // toggle just keeps its default.
    }
  }

  Future<void> _setSounds(bool on) async {
    setState(() => _sounds = on);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSounds, on);
    } catch (_) {}
  }

  Future<void> _load() async {
    if (mounted && !_loading) setState(() => _loading = true);
    var failed = false;
    final results = await Future.wait([
      _streaks.getStreakCount(widget.childId).timeout(_readTimeout).catchError(
        (Object _) {
          failed = true;
          return 0;
        },
      ),
      _streaks
          .getRecentSessions(widget.childId, limit: 200)
          .timeout(_readTimeout)
          .catchError((Object _) {
            failed = true;
            return <HomeworkSession>[];
          }),
    ]);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = failed;
      _streak = results[0] as int;
      _sessions = results[1] as List<HomeworkSession>;
    });
  }

  int get _completed => _sessions.where((s) => s.isCompleted).length;

  KidLevel get _level => KidLevel(_completed);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.green,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          6,
          AppSpacing.screenPadding,
          28,
        ),
        children: [
          Text('Me', style: AppText.display(size: 28)),
          const SizedBox(height: 16),
          _identityCard(),
          const SizedBox(height: 22),
          const DfSectionLabel('This is you'),
          if (_loading) const ShimmerCard(lines: 3) else _statsCard(),
          const SizedBox(height: 22),
          const DfSectionLabel('My app'),
          _prefsCard(),
          if (widget.onUnpair != null) ...[
            const SizedBox(height: 22),
            const DfSectionLabel('This device'),
            _deviceCard(),
          ],
        ],
      ),
    );
  }

  Widget _identityCard() {
    final lvl = _level;
    // Level and XP are derived from completed sessions, so if the read
    // failed they are not "Level 1" — they are unknown, and saying
    // Level 1 to a kid who is Level 4 is worse than saying nothing.
    final known = !_loading && !_failed;
    return DfCard(
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Column(
        children: [
          Row(
            children: [
              DfAvatar(_initial, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.childName, style: AppText.title(size: 20)),
                    const SizedBox(height: 4),
                    Text(
                      known
                          ? 'Level ${lvl.level} · ${lvl.title}'
                          : 'Level —',
                      style: AppText.bodySecondary(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (known) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: lvl.progress,
                minHeight: 8,
                backgroundColor: AppColors.border2,
                valueColor: const AlwaysStoppedAnimation(AppColors.green),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${lvl.xpIntoLevel} / ${KidLevel.xpPerLevel} XP',
                  style: AppText.caption(),
                ),
                Text(
                  '${lvl.xpToNext} XP to Level ${lvl.level + 1}',
                  style: AppText.caption(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statsCard() {
    String stat(String Function() render) => _failed ? '—' : render();
    return DfCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: DfStatTile(
                stat(() => '$_streak'),
                'day streak',
                valueColor: AppColors.amberDeep,
                align: CrossAxisAlignment.center,
              ),
            ),
          ),
          _divider(),
          Expanded(
            child: Center(
              child: DfStatTile(
                stat(() => '$_completed'),
                _completed == 1 ? 'session' : 'sessions',
                align: CrossAxisAlignment.center,
              ),
            ),
          ),
          _divider(),
          Expanded(
            child: Center(
              child: DfStatTile(
                stat(() => '${_level.totalXp}'),
                'XP earned',
                align: CrossAxisAlignment.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _prefsCard() => DfCard(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
    child: Row(
      children: [
        const Icon(LucideIcons.volume2, size: 20, color: AppColors.ink70),
        const SizedBox(width: 14),
        Expanded(child: Text('Sounds', style: AppText.listTitle())),
        Switch(
          value: _sounds,
          activeThumbColor: AppColors.card,
          activeTrackColor: AppColors.green,
          onChanged: _setSounds,
        ),
      ],
    ),
  );

  Widget _deviceCard() => DfCard(
    padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paired to ${widget.childName}',
          style: AppText.cardHeader(size: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'Unpairing signs this device out. A parent has to set it up '
          'again with a new code.',
          style: AppText.bodySecondary(),
        ),
        const SizedBox(height: 14),
        DfButton.outline(
          'Unpair this device',
          onPressed: () => widget.onUnpair?.call(),
        ),
      ],
    ),
  );

  Widget _divider() =>
      Container(width: 1, height: 34, color: AppColors.border2);

  String get _initial {
    final n = widget.childName.trim();
    return n.isEmpty ? '?' : n.substring(0, 1).toUpperCase();
  }
}
