import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../utils/subjects.dart';

const List<String> weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

// Single-letter column headers for the mini week chart (M T W T F S S).
const List<String> _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class SessionStatsScreen extends StatefulWidget {
  final String childName;

  const SessionStatsScreen({super.key, required this.childName});

  @override
  State<SessionStatsScreen> createState() => _SessionStatsScreenState();
}

class _SessionStatsScreenState extends State<SessionStatsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _stats;
  List<int> _weeklyMinutes = List.filled(7, 0);
  // Per-subject minutes breakdown. The map is ordered by the
  // canonical kSubjects list so the UI shows Math before English
  // regardless of which subject had more study time.
  final Map<String, int> _subjectMinutes = {for (final s in kSubjects) s: 0};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final families = await supabase
        .from('families')
        .select('id')
        .eq('parent_id', user.id)
        .maybeSingle();
    if (families == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final familyId = families['id'];

    final children = await supabase
        .from('children')
        .select('id')
        .eq('family_id', familyId)
        .eq('name', widget.childName)
        .maybeSingle();
    if (children == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final childId = children['id'] as String;

    final sessions = await supabase
        .from('homework_sessions')
        .select('id, created_at, duration_minutes, status')
        .eq('child_id', childId)
        .order('created_at', ascending: false);

    // Pull all tasks for all sessions in one go so we can attribute
    // study time to subjects. Without this we'd be looking at the
    // session-level row only, which has no subject.
    final sessionIds = sessions
        .map((s) => s['id'] as String)
        .toList(growable: false);
    final List<dynamic> allTasks = sessionIds.isEmpty
        ? const []
        : await supabase
              .from('homework_tasks')
              .select('subject, session_id')
              .inFilter('session_id', sessionIds);

    final totalSessions = sessions.length;
    int totalMinutes = 0;
    int completed = 0;
    int cancelled = 0;
    int approvedProofs = 0;

    for (final s in sessions) {
      totalMinutes += (s['duration_minutes'] as int?) ?? 0;
      if (s['status'] == 'completed') completed++;
      if (s['status'] == 'cancelled') cancelled++;
    }

    // Count approved proofs once for all sessions in a single query,
    // then aggregate by session_id client-side. Previously this was
    // done one query per session inside the loop above (N+1), which
    // got noticeably slow for kids with a long history.
    final approvedBySession = <String, int>{};
    if (sessionIds.isNotEmpty) {
      final approvedProofsResp = await supabase
          .from('proof_submissions')
          .select('session_id, status')
          .inFilter('session_id', sessionIds)
          .eq('status', 'approved');
      for (final p in approvedProofsResp) {
        final sid = p['session_id'] as String?;
        if (sid == null) continue;
        approvedBySession[sid] = (approvedBySession[sid] ?? 0) + 1;
      }
    }
    approvedProofs = approvedBySession.values.fold(0, (a, b) => a + b);

    // Per-subject minutes. We sum session duration for every task
    // tagged with that subject. A 60-min session with 1 Math task +
    // 1 English task attributes 60 min to each, which roughly
    // reflects actual studying (they didn't do nothing for half the
    // time) but does over-count when sessions mix subjects heavily.
    // For a v1, this is good enough.
    final sessionMinutes = <String, int>{
      for (final s in sessions)
        s['id'] as String: (s['duration_minutes'] as int?) ?? 0,
    };
    for (final t in allTasks) {
      final sid = t['session_id'] as String?;
      final subject = normalizeSubject(t['subject'] as String?);
      if (sid == null) continue;
      _subjectMinutes[subject] =
          (_subjectMinutes[subject] ?? 0) + (sessionMinutes[sid] ?? 0);
    }

    if (!mounted) return;
    setState(() {
      // Weekly breakdown
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final weekMinutes = List.filled(7, 0);
      for (final s in sessions) {
        final started = DateTime.tryParse(s['created_at'] as String? ?? '');
        if (started != null &&
            started.isAfter(startOfWeek.subtract(const Duration(days: 1)))) {
          final dayIndex = started.weekday - 1;
          if (dayIndex >= 0 && dayIndex < 7) {
            weekMinutes[dayIndex] += (s['duration_minutes'] as int?) ?? 0;
          }
        }
      }

      _stats = {
        'total_sessions': totalSessions,
        'total_minutes': totalMinutes,
        'completed': completed,
        'cancelled': cancelled,
        'approved_proofs': approvedProofs,
      };
      _weeklyMinutes = weekMinutes;
      _loading = false;
    });
  }

  // ── Formatting helpers ───────────────────────────────────────────

  /// "5h 20m", "45m", or "0m" from a minute count.
  String _fmtDuration(int minutes) {
    if (minutes <= 0) return '0m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: Text('Activity', style: AppText.screenTitle())),
      body: _loading
          ? _loadingState()
          : ((_stats?['total_sessions'] as int?) ?? 0) == 0
          ? _emptyState()
          : _content(),
    );
  }

  Widget _loadingState() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        _skeleton(height: 44),
        const SizedBox(height: 18),
        _skeleton(height: 170),
        const SizedBox(height: 14),
        _skeleton(height: 96),
        const SizedBox(height: 14),
        _skeleton(height: 120),
      ],
    );
  }

  Widget _skeleton({required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.borderCol),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subtitle(),
          const SizedBox(height: 40),
          DfEmptyState(
            icon: LucideIcons.activity,
            title: 'No focus sessions yet',
            hint:
                'When ${widget.childName} starts focusing, history, streaks '
                'and gentle insights show up here.',
          ),
        ],
      ),
    );
  }

  Widget _subtitle() {
    return Text(
      'History, streaks and gentle insight — never a report card.',
      style: AppText.body(size: 14),
    );
  }

  Widget _content() {
    final weekTotal = _weeklyMinutes.fold<int>(0, (a, b) => a + b);
    final total = (_stats?['total_sessions'] as int?) ?? 0;
    final completed = (_stats?['completed'] as int?) ?? 0;
    final totalMinutes = (_stats?['total_minutes'] as int?) ?? 0;
    final approvedPct = total == 0 ? 0 : ((completed / total) * 100).round();
    final avgFocus = total == 0 ? 0 : (totalMinutes / total).round();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        _subtitle(),
        const SizedBox(height: 16),
        // Filter row — this screen scopes to a single kid, so the chip
        // reflects the kid rather than the mock's "All kids".
        Row(
          children: [
            const DfChip('This week', selected: true),
            const Spacer(),
            DfChip(widget.childName, icon: LucideIcons.user),
          ],
        ),
        const SizedBox(height: 16),
        _focusedCard(weekTotal),
        const SizedBox(height: 14),
        DfCard(
          child: Row(
            children: [
              Expanded(
                child: DfStatTile(
                  '$total',
                  'sessions',
                  align: CrossAxisAlignment.center,
                ),
              ),
              _tileDivider(),
              Expanded(
                child: DfStatTile(
                  '$approvedPct%',
                  'approved',
                  valueColor: AppColors.green,
                  align: CrossAxisAlignment.center,
                ),
              ),
              _tileDivider(),
              Expanded(
                child: DfStatTile(
                  _fmtDuration(avgFocus),
                  'avg focus',
                  align: CrossAxisAlignment.center,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _insightCard(),
        const SizedBox(height: 22),
        const DfSectionLabel('Time by subject'),
        _subjectBreakdown(),
        const SizedBox(height: 22),
        const DfSectionLabel('Completion'),
        _completionCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _tileDivider() =>
      Container(width: 1, height: 34, color: AppColors.line);

  Widget _focusedCard(int weekTotal) {
    final maxMinutes = _weeklyMinutes.fold<int>(0, (m, v) => v > m ? v : m);
    final todayIndex = DateTime.now().weekday - 1;
    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Focused this week', style: AppText.label()),
          const SizedBox(height: 8),
          Text(_fmtDuration(weekTotal), style: AppText.display(size: 38)),
          const SizedBox(height: 18),
          SizedBox(
            height: 116,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final minutes = _weeklyMinutes[i];
                final barHeight = maxMinutes > 0
                    ? (minutes / maxMinutes) * 84
                    : 0.0;
                final isToday = i == todayIndex;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (minutes > 0)
                          Text('${minutes}m', style: AppText.caption(size: 9)),
                        const SizedBox(height: 3),
                        Container(
                          height: barHeight.clamp(4.0, 84.0),
                          decoration: BoxDecoration(
                            color: isToday
                                ? AppColors.green
                                : AppColors.green.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _weekdayInitials[i],
                          style: AppText.caption(
                            size: 11,
                            color: isToday ? AppColors.green : AppColors.ink45,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// Derives the single most-focused weekday this week and frames it
  /// as the mock's gentle insight line. Falls back to a neutral nudge
  /// when the week has no focus time yet.
  Widget _insightCard() {
    int bestIdx = -1;
    int bestVal = 0;
    for (var i = 0; i < _weeklyMinutes.length; i++) {
      if (_weeklyMinutes[i] > bestVal) {
        bestVal = _weeklyMinutes[i];
        bestIdx = i;
      }
    }
    final String title;
    final String body;
    if (bestIdx < 0) {
      title = 'A calm week so far';
      body =
          '${widget.childName} hasn\'t focused yet this week — the next '
          'session starts the streak.';
    } else {
      title = '${widget.childName} focuses best on ${weekdayNames[bestIdx]}';
      body =
          '${_fmtDuration(bestVal)} of focused work — their strongest day '
          'this week.';
    }
    return DfCard(
      color: AppColors.greenTint,
      borderColor: AppColors.greenTint,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.iconTile),
            ),
            child: const Icon(
              LucideIcons.sparkles,
              size: 19,
              color: AppColors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardHeader(size: 15)),
                const SizedBox(height: 4),
                Text(body, style: AppText.bodySecondary(size: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subjectBreakdown() {
    final entries = _subjectMinutes.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return DfCard(
        child: Text(
          'Tag tasks with a subject to see a per-subject breakdown.',
          style: AppText.bodySecondary(size: 13),
        ),
      );
    }
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((e) {
            final pct = total == 0 ? 0.0 : e.value / total;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(e.key, style: AppText.listTitle(size: 14)),
                      ),
                      Text('${e.value} min', style: AppText.caption()),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor: AppColors.green.withValues(alpha: 0.1),
                      color: AppColors.green,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _completionCard() {
    final total = (_stats?['total_sessions'] as int?) ?? 0;
    final completed = (_stats?['completed'] as int?) ?? 0;
    final approvedProofs = (_stats?['approved_proofs'] as int?) ?? 0;
    if (total == 0) {
      return DfCard(
        child: Text('No sessions yet', style: AppText.bodySecondary()),
      );
    }
    final rate = completed / total;
    final percent = (rate * 100).round();
    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sessions completed',
                  style: AppText.cardHeader(size: 15),
                ),
              ),
              DfStatusPill('$percent%', tone: DfPillTone.success),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 12,
              backgroundColor: AppColors.border2,
              valueColor: const AlwaysStoppedAnimation(AppColors.green),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$completed of $total sessions completed · '
            '$approvedProofs proofs approved',
            style: AppText.bodySecondary(size: 13),
          ),
        ],
      ),
    );
  }
}
