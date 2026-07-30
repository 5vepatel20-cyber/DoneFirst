import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../utils/kid_level.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../widgets/error_banner.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/proof_thumbnail.dart';
import 'proof_image_viewer.dart';

class KidHistoryScreen extends StatefulWidget {
  final String childId;
  final String childName;

  /// True when rendered as the Progress tab inside KidShell, which
  /// owns the Scaffold and the tab bar. Standalone (the parent's "Kid
  /// view" path) it keeps its own Scaffold and AppBar.
  final bool embedded;

  const KidHistoryScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.embedded = false,
  });

  @override
  State<KidHistoryScreen> createState() => _KidHistoryScreenState();
}

class _KidHistoryScreenState extends State<KidHistoryScreen> {
  final _sessionService = SessionService();
  final _proofService = ProofService();
  List<HomeworkSession> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _sessions = await _sessionService.getHistory(widget.childId);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  String _formatDuration(HomeworkSession s) {
    // Shares _durationOf so a single session's label can never
    // disagree with the totals row below it. Going through the
    // unclamped subtraction here used to make a row whose ended_at
    // precedes its started_at read as a plausible-but-invented
    // duration: Dart's `%` is non-negative for a positive divisor, so
    // -1h59m came out as inHours -1 (failing `h > 0`) and inMinutes
    // % 60 == 1, printing "1m" while _durationOf counted it as zero.
    // Rows like that exist from before timestamps were written in UTC
    // (see utils/db_time.dart), so this has to hold for real data.
    final diff = _durationOf(s);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  // ── Presentational XP / level layer over real session data ────────
  // XP and levels are a friendly surface on top of the sessions this
  // screen already loads — no new services or persistence. The maths
  // lives in utils/kid_level.dart because the Me tab shows the same
  // level and the same "N XP to Level M", and two copies is how one
  // tab ends up calling a kid Level 4 while the next calls them 5.
  static const int _xpPerSession = KidLevel.xpPerSession;
  static const int _xpPerLevel = KidLevel.xpPerLevel;

  Duration _durationOf(HomeworkSession s) {
    final end = s.endedAt ?? DateTime.now();
    final d = end.difference(s.startedAt);
    return d.isNegative ? Duration.zero : d;
  }

  List<HomeworkSession> get _completed =>
      _sessions.where((s) => s.isCompleted).toList();

  int get _totalXp => _completed.length * _xpPerSession;
  int get _level => (_totalXp ~/ _xpPerLevel) + 1;
  int get _xpIntoLevel => _totalXp % _xpPerLevel;
  int get _xpToNext => _xpPerLevel - _xpIntoLevel;

  String _levelTitle(int lvl) => KidLevel.titleFor(lvl);

  String _fmtMinutes(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
          ? ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: const [
                ShimmerCard(lines: 4),
                SizedBox(height: 14),
                ShimmerCard(lines: 2),
                SizedBox(height: 14),
                ShimmerCard(lines: 4),
              ],
            )
          : _error != null
          ? RetryWidget(message: _error!, onRetry: _load)
          : _sessions.isEmpty
          ? DfEmptyState(
              icon: LucideIcons.trendingUp,
              title: 'No progress yet',
              hint:
                  'Finish a focus session and watch your XP climb '
                  'and your streak grow.',
              ctaLabel: 'Refresh',
              onCta: _load,
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.green,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                  vertical: 12,
                ),
                children: [
                  _buildLevelHero(),
                  const SizedBox(height: AppSpacing.blockGap),
                  _buildWeekStats(),
                  const SizedBox(height: AppSpacing.blockGap),
                  _buildWeekChart(),
                  const SizedBox(height: AppSpacing.blockGap),
                  _buildLevelLadder(),
                  const SizedBox(height: AppSpacing.blockGap),
                  _buildRecentSessions(),
                ],
              ),
            );

    // As a tab inside KidShell the Scaffold and the bottom inset
    // belong to the shell, and an AppBar here would render a second
    // title bar with a back arrow that pops the whole kid app.
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: Text('Progress', style: AppText.screenTitle())),
      body: body,
    );
  }

  /// Level hero — big level badge, title, and an XP progress bar.
  Widget _buildLevelHero() {
    final lvl = _level;
    final frac = (_xpIntoLevel / _xpPerLevel).clamp(0.0, 1.0);
    return DfCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.green,
                  borderRadius: BorderRadius.circular(AppRadius.tile),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$lvl',
                  style: AppText.display(size: 28, color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Level $lvl', style: AppText.title(size: 20)),
                    Text(
                      _levelTitle(lvl),
                      style: AppText.bodySecondary(color: AppColors.green),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_xpIntoLevel / $_xpPerLevel XP',
                style: AppText.listTitle(),
              ),
              Text(
                '$_xpToNext XP to Level ${lvl + 1}',
                style: AppText.bodySecondary(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 10,
              backgroundColor: AppColors.border2,
              valueColor: const AlwaysStoppedAnimation(AppColors.green),
            ),
          ),
        ],
      ),
    );
  }

  /// "This week" — focused time, session count, day streak.
  Widget _buildWeekStats() {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final week = _sessions.where((s) => s.startedAt.isAfter(weekAgo)).toList();
    final weekMinutes = week.fold<int>(
      0,
      (sum, s) => sum + _durationOf(s).inMinutes,
    );

    // Day streak — consecutive days up to today with at least one session.
    final dayKeys = _sessions
        .map(
          (s) => DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day),
        )
        .toSet();
    int streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
    while (dayKeys.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DfSectionLabel('This week'),
          Row(
            children: [
              Expanded(
                child: DfStatTile(
                  _fmtMinutes(weekMinutes),
                  'focused',
                  valueColor: AppColors.green,
                ),
              ),
              Expanded(child: DfStatTile('${week.length}', 'sessions')),
              Expanded(
                child: DfStatTile(
                  '$streak',
                  'day streak',
                  valueColor: AppColors.amber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Focus each day" — a Mon–Sun bar chart of the current week.
  Widget _buildWeekChart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final minutes = List<int>.filled(7, 0);
    for (final s in _sessions) {
      final d = DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day);
      final idx = d.difference(monday).inDays;
      if (idx >= 0 && idx < 7) minutes[idx] += _durationOf(s).inMinutes;
    }
    final maxM = minutes.fold<int>(0, (a, b) => b > a ? b : a);
    final bestIdx = maxM == 0 ? -1 : minutes.indexOf(maxM);
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DfSectionLabel('Focus each day'),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final frac = maxM == 0 ? 0.0 : minutes[i] / maxM;
                final isBest = i == bestIdx;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: (frac * 90).clamp(4.0, 90.0),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: isBest
                              ? AppColors.green
                              : minutes[i] == 0
                              ? AppColors.border2
                              : AppColors.greenTint,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        labels[i],
                        style: AppText.caption(
                          color: isBest ? AppColors.green : AppColors.ink45,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            bestIdx < 0
                ? 'No focus time logged yet this week.'
                : 'Best day · ${dayNames[bestIdx]} — ${_fmtMinutes(maxM)} focused',
            style: AppText.bodySecondary(),
          ),
        ],
      ),
    );
  }

  /// "Levels" ladder — current tier, the next one, and a distant goal.
  Widget _buildLevelLadder() {
    final lvl = _level;
    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DfSectionLabel('Levels'),
          _ladderRow(
            level: lvl,
            title: _levelTitle(lvl),
            subtitle: 'Level $lvl · you’re here',
            here: true,
          ),
          const SizedBox(height: 10),
          _ladderRow(
            level: lvl + 1,
            title: _levelTitle(lvl + 1),
            subtitle: 'Level ${lvl + 1} · $_xpToNext XP away',
          ),
          const SizedBox(height: 10),
          _ladderRow(
            level: lvl < 8 ? 8 : lvl + 4,
            title: _levelTitle(lvl < 8 ? 8 : lvl + 4),
            subtitle: 'Level ${lvl < 8 ? 8 : lvl + 4} · the big one',
          ),
        ],
      ),
    );
  }

  Widget _ladderRow({
    required int level,
    required String title,
    required String subtitle,
    bool here = false,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: here ? AppColors.green : AppColors.border2,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          alignment: Alignment.center,
          child: Text(
            '$level',
            style: AppText.statValue(
              size: 18,
              color: here ? Colors.white : AppColors.ink70,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.listTitle()),
              Text(subtitle, style: AppText.bodySecondary(size: 12)),
            ],
          ),
        ),
        if (here) const DfStatusPill('You', tone: DfPillTone.success),
      ],
    );
  }

  /// Recent sessions — tap a row to review its proofs.
  Widget _buildRecentSessions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DfSectionLabel('Recent sessions'),
        ..._sessions.take(10).map((s) {
          // startedAt is a UTC DateTime (timestamptz); grouping by the
          // UTC date files an 8pm session under tomorrow.
          final started = s.startedAt.toLocal().toIso8601String();
          final date = started.length >= 10
              ? started.substring(0, 10)
              : started;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DfCard(
              onTap: () => _showProofs(s.id),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          (s.isCompleted
                                  ? AppColors.green
                                  : s.isActive
                                  ? AppColors.amber
                                  : AppColors.ink45)
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      s.isCompleted
                          ? LucideIcons.checkCircle2
                          : s.isActive
                          ? LucideIcons.playCircle
                          : LucideIcons.circle,
                      size: 20,
                      color: s.isCompleted
                          ? AppColors.green
                          : s.isActive
                          ? AppColors.amber
                          : AppColors.ink45,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(date, style: AppText.listTitle()),
                        Text(
                          '${_formatDuration(s)} · ${s.status}',
                          style: AppText.bodySecondary(size: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: AppColors.ink45,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _showProofs(String sessionId) async {
    try {
      final proofs = await _proofService.getProofsForSession(sessionId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Your Proofs')),
            body: proofs.isEmpty
                ? const Center(child: Text('No proofs submitted'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: proofs.length,
                    itemBuilder: (ctx, i) {
                      final p = proofs[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (p.imageUrl.isNotEmpty)
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProofImageViewer(
                                      imageUrl: p.imageUrl,
                                      taskDescription: p.taskDescription ?? '',
                                      aiResult: p,
                                    ),
                                  ),
                                ),
                                child: ProofThumbnail(
                                  url: p.imageUrl,
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(8),
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.taskDescription ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          (p.aiDecision == 'approved'
                                                  ? AppColors.success
                                                  : p.aiDecision == 'rejected'
                                                  ? AppColors.danger
                                                  : AppColors.accent)
                                              .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      p.isApproved
                                          ? 'Approved'
                                          : p.isRejected
                                          ? 'Rejected'
                                          : 'Waiting for parent',
                                      style: TextStyle(
                                        color: p.isApproved
                                            ? AppColors.success
                                            : p.isRejected
                                            ? AppColors.danger
                                            : AppColors.accent,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t load proofs: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}
