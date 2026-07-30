import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/homework_session.dart';
import '../../models/homework_task.dart';
import '../../services/proof_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/df_kit.dart';
import '../../widgets/shimmer_loading.dart';

/// The "Kid · Tasks" tab: each task from today's session, its status,
/// and nothing the kid can get wrong.
///
/// READ-ONLY ON PURPOSE
///
/// This tab is only reachable from [KidShell], which only renders in
/// the *free-time* state. If a session were running the kid would be on
/// LockedScreen, which already owns the design's in-session flow —
/// add-task, snap proof, resubmit. So by construction there is no
/// active session to act on here, and offering "Add proof" would mean
/// attaching a photo to work that is already finished and graded.
///
/// What this screen is for is the question a kid actually asks during
/// free time: *did my homework go through?* It answers per task, and
/// says plainly when a task still needs another photo — that one is
/// recoverable, but only in the next session, so it is stated rather
/// than turned into a dead button.
///
/// Every table it touches is one the kid's JWT can read under RLS
/// (`homework_sessions`, `homework_tasks`, `proof_submissions`); it
/// deliberately never reads `children`, which kids have no policy for.
class KidTasksScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const KidTasksScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<KidTasksScreen> createState() => _KidTasksScreenState();
}

class _KidTasksScreenState extends State<KidTasksScreen> {
  final _sessions = SessionService();
  final _proofs = ProofService();

  bool _loading = true;
  bool _failed = false;
  HomeworkSession? _todaySession;
  List<HomeworkTask> _tasks = const [];

  /// Same ceiling as the Today tab. A postgrest call that never
  /// completes has no error to catch, and without a bound this tab
  /// would sit on its shimmer forever with no way to retry.
  static const Duration _readTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(KidTasksScreen old) {
    super.didUpdateWidget(old);
    if (widget.childId != old.childId) _load();
  }

  Future<void> _load() async {
    if (mounted && !_loading) setState(() => _loading = true);
    try {
      final history = await _sessions
          .getHistory(widget.childId)
          .timeout(_readTimeout);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      HomeworkSession? picked;
      for (final s in history) {
        // startedAt is UTC (Postgres timestamptz); compare on the
        // kid's local calendar day or an evening session reads as
        // tomorrow's. Same trap as utils/db_time.dart documents.
        final local = s.startedAt.toLocal();
        if (DateTime(local.year, local.month, local.day) != today) continue;
        // getHistory is ordered started_at desc, so the first match is
        // the most recent session today.
        picked = s;
        break;
      }

      var tasks = const <HomeworkTask>[];
      if (picked != null) {
        tasks = await _proofs.getTasks(picked.id).timeout(_readTimeout);
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = false;
        _todaySession = picked;
        _tasks = tasks;
      });
    } catch (e) {
      debugPrint('KidTasksScreen: load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  int get _done => _tasks.where((t) => t.isApproved).length;

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
          Text('Today’s tasks', style: AppText.display(size: 28)),
          const SizedBox(height: 14),
          if (_loading)
            const ShimmerCard(lines: 4)
          else if (_failed)
            _retryCard()
          else if (_todaySession == null)
            _noSessionCard()
          else if (_tasks.isEmpty)
            _noTasksCard()
          else ...[
            _summary(),
            const SizedBox(height: 18),
            ..._tasks.map(_taskRow),
          ],
        ],
      ),
    );
  }

  Widget _summary() {
    final all = _tasks.length;
    final allApproved = _done == all;
    return DfCard(
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Row(
        children: [
          _iconTile(
            allApproved ? LucideIcons.check : LucideIcons.listChecks,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allApproved ? 'All approved' : '$_done of $all approved',
                  style: AppText.cardHeader(),
                ),
                const SizedBox(height: 4),
                Text(
                  allApproved
                      ? 'Everything you sent went through. Nice work.'
                      : 'Anything still waiting will finish in your next '
                            'session.',
                  style: AppText.bodySecondary(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskRow(HomeworkTask t) {
    final ({String label, IconData icon, DfPillTone tone}) s = _statusOf(t);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DfCard(
        padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(s.icon, size: 20, color: _toneColor(s.tone)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.description.isEmpty ? t.subject : t.description,
                    style: AppText.cardHeader(size: 15),
                  ),
                  if (t.subject.isNotEmpty && t.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(t.subject, style: AppText.caption()),
                  ],
                  const SizedBox(height: 8),
                  DfStatusPill(s.label, tone: s.tone),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  ({String label, IconData icon, DfPillTone tone}) _statusOf(HomeworkTask t) {
    if (t.isApproved) {
      return (
        label: 'Approved',
        icon: LucideIcons.circleCheck,
        tone: DfPillTone.success,
      );
    }
    if (t.isSubmitted) {
      return (
        label: 'Checking your photo…',
        icon: LucideIcons.clock,
        tone: DfPillTone.info,
      );
    }
    if (t.isRejected) {
      return (
        label: 'Needs another photo',
        icon: LucideIcons.rotateCcw,
        tone: DfPillTone.attention,
      );
    }
    return (
      label: 'Not started',
      icon: LucideIcons.circle,
      tone: DfPillTone.neutral,
    );
  }

  Color _toneColor(DfPillTone tone) => switch (tone) {
    DfPillTone.success => AppColors.green,
    DfPillTone.attention => AppColors.amber,
    DfPillTone.danger => AppColors.danger,
    DfPillTone.info => AppColors.info,
    DfPillTone.neutral => AppColors.ink45,
  };

  Widget _retryCard() => DfCard(
    padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
    child: Row(
      children: [
        _iconTile(
          LucideIcons.wifiOff,
          bg: AppColors.border2,
          fg: AppColors.ink70,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Couldn’t load your tasks just now.',
            style: AppText.bodySecondary(),
          ),
        ),
        TextButton(
          onPressed: _load,
          child: Text(
            'Try again',
            style: AppText.caption().copyWith(color: AppColors.green),
          ),
        ),
      ],
    ),
  );

  Widget _noSessionCard() => const DfEmptyState(
    icon: LucideIcons.coffee,
    title: 'Nothing to do right now',
    hint: 'No homework session today yet. When a parent starts one, '
        'your tasks show up here.',
  );

  Widget _noTasksCard() => const DfEmptyState(
    icon: LucideIcons.listChecks,
    title: 'No tasks on today’s session',
    hint: 'Your session didn’t have any tasks added to it.',
  );

  Widget _iconTile(IconData icon, {Color? bg, Color? fg}) => Container(
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
