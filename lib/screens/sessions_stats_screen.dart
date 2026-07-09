import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../utils/subjects.dart';

const List<String> weekdayNames = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

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
  final Map<String, int> _subjectMinutes = {
    for (final s in kSubjects) s: 0,
  };

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final families = await supabase
        .from('families')
        .select('id')
        .eq('parent_id', user.id)
        .maybeSingle();
    if (families == null) return;
    final familyId = families['id'];

    final children = await supabase
        .from('children')
        .select('id')
        .eq('family_id', familyId)
        .eq('name', widget.childName)
        .maybeSingle();
    if (children == null) return;
    final childId = children['id'] as String;

    final sessions = await supabase
        .from('homework_sessions')
        .select('id, created_at, duration_minutes, status')
        .eq('child_id', childId)
        .order('created_at', ascending: false);

    // Pull all tasks for all sessions in one go so we can attribute
    // study time to subjects. Without this we'd be looking at the
    // session-level row only, which has no subject.
    final sessionIds =
        sessions.map((s) => s['id'] as String).toList(growable: false);
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
      for (final s in sessions) s['id'] as String: (s['duration_minutes'] as int?) ?? 0,
    };
    for (final t in allTasks) {
      final sid = t['session_id'] as String?;
      final subject = normalizeSubject(t['subject'] as String?);
      if (sid == null) continue;
      _subjectMinutes[subject] =
          (_subjectMinutes[subject] ?? 0) + (sessionMinutes[sid] ?? 0);
    }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.childName}\'s Stats')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _statCard(
                  Icons.play_circle,
                  'Total Sessions',
                  '${_stats?['total_sessions'] ?? 0}',
                  AppColors.primary,
                ),
                const SizedBox(height: 12),
                _statCard(
                  Icons.timer,
                  'Total Study Time',
                  '${_stats?['total_minutes'] ?? 0} min',
                  AppColors.accent,
                ),
                const SizedBox(height: 12),
                _statCard(
                  Icons.check_circle,
                  'Completed',
                  '${_stats?['completed'] ?? 0}',
                  AppColors.success,
                ),
                const SizedBox(height: 12),
                _statCard(
                  Icons.cancel,
                  'Cancelled',
                  '${_stats?['cancelled'] ?? 0}',
                  AppColors.danger,
                ),
                const SizedBox(height: 12),
                _statCard(
                  Icons.verified,
                  'Proofs Approved',
                  '${_stats?['approved_proofs'] ?? 0}',
                  AppColors.info,
                ),
                const SizedBox(height: 24),
                _buildWeeklyChart(),
                const SizedBox(height: 24),
                _buildSubjectBreakdown(),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Completion Rate',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildRateBar(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSubjectBreakdown() {
    final entries = _subjectMinutes.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Tag tasks with a subject to see a per-subject breakdown.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Time by Subject',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...entries.map((e) {
              final pct = total == 0 ? 0.0 : e.value / total;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${e.value} min',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.1),
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRateBar() {
    final total = (_stats?['total_sessions'] as int?) ?? 0;
    final completed = (_stats?['completed'] as int?) ?? 0;
    if (total == 0)
      return const Text(
        'No sessions yet',
        style: TextStyle(color: AppColors.textSecondary),
      );

    final rate = completed / total;
    final percent = (rate * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: rate,
            minHeight: 12,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(AppColors.success),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$percent% of sessions completed successfully',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildWeeklyChart() {
    final maxMinutes = _weeklyMinutes.reduce((a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This Week',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (i) {
                  final minutes = _weeklyMinutes[i];
                  final height = maxMinutes > 0
                      ? (minutes / maxMinutes) * 100
                      : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (minutes > 0)
                            Text(
                              '${minutes}m',
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Container(
                            height: height.clamp(4.0, 100.0),
                            decoration: BoxDecoration(
                              color: i == DateTime.now().weekday - 1
                                  ? AppColors.primary
                                  : AppColors.primary.withValues(alpha:0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            weekdayNames[i],
                            style: TextStyle(
                              fontSize: 9,
                              color: i == DateTime.now().weekday - 1
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
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
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
