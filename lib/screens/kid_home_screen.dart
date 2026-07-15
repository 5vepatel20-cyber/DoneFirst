import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/models.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../services/break_service.dart';
import '../services/notification_service.dart';
import '../services/streak_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ring_timer.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/milestone_celebration.dart';
import '../widgets/session_complete_celebration.dart';
import '../services/milestone_service.dart';
import 'task_entry_screen.dart';
import 'kid_history_screen.dart';

class KidHomeScreen extends StatefulWidget {
  final String childId;
  final String childName;
  const KidHomeScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<KidHomeScreen> createState() => _KidHomeScreenState();
}

class _KidHomeScreenState extends State<KidHomeScreen> {
  final _sessionService = SessionService();
  final _proofService = ProofService();
  final _breakService = BreakService();
  final _notificationService = NotificationService();
  final _streakService = StreakService();
  int _streak = 0;
  // True when the current streak is being held up by a grace day.
  // Surfaced in the streak card so the kid (and parent) can see
  // that the streak didn't break — it just got help.
  bool _streakGraceUsed = false;
  int _previousStreak = 0;
  HomeworkSession? _activeSession;
  List<HomeworkTask> _tasks = [];
  List<ProofSubmission> _proofs = [];
  bool _loading = true;
  Timer? _refreshTimer;
  Timer? _tickTimer;
  // _now is bumped every second so the kid-side ring progress
  // climbs smoothly without a full data refresh. The 15-second
  // _refreshTimer still handles server-state changes (new task,
  // session removed, etc.).
  DateTime _now = DateTime.now();
  bool _breakRequested = false;
  MilestoneInfo? _currentMilestone;
  bool _showSessionComplete = false;
  bool _hadActiveSession = false;
  final _milestoneService = MilestoneService();

  @override
  void initState() {
    super.initState();
    _checkActive();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkActive(),
    );
    _tickTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkActive() async {
    // Active session lookup is the gating read — only after we know
    // its id can we fetch tasks + proofs. Streak is independent and
    // can fire alongside the session lookup.
    final results = await Future.wait([
      _sessionService.getActiveSession(widget.childId),
      _streakService.computeStreakResult(widget.childId),
    ]);
    final newSession = results[0] as HomeworkSession?;
    final newStreak = (results[1] as StreakResult).streak;
    final newStreakGraceUsed = (results[1] as StreakResult).graceUsed;
    if (!mounted) return;
    if (newSession != null) {
      // Tasks + proofs + latest break request are independent —
      // fetch in parallel instead of three sequential round-trips.
      // The break lookup keeps the "Ask for a break" button in
      // sync with server state (so it re-enables after the parent
      // responds, instead of staying stuck on "Requested" forever).
      final sessionResults = await Future.wait([
        _proofService.getTasks(newSession.id),
        _proofService.getProofsForSession(newSession.id),
        _breakService.getLatestForSession(newSession.id),
      ]);
      if (mounted) {
        setState(() {
          _tasks = sessionResults[0] as List<HomeworkTask>;
          _proofs = sessionResults[1] as List<ProofSubmission>;
          // True only if there's a pending request. Approved/denied
          // /no request → re-enable the button.
          _breakRequested = sessionResults[2] != null &&
              (sessionResults[2] as BreakRequest).status == 'pending';
        });
      }
    }
    if (_hadActiveSession && newSession == null && _activeSession != null) {
      setState(() {
        _showSessionComplete = true;
        _streak = newStreak;
        _streakGraceUsed = newStreakGraceUsed;
      });
      _previousStreak = newStreak;
    } else {
      if (newStreak > _previousStreak) {
        final milestone = _milestoneService.wasMilestoneReached(
          _previousStreak,
          newStreak,
        );
        if (milestone != null) {
          setState(() => _currentMilestone = milestone);
        }
      }
      _previousStreak = newStreak;
      setState(() {
        _streak = newStreak;
        _streakGraceUsed = newStreakGraceUsed;
      });
    }
    _hadActiveSession = newSession != null;
    _activeSession = newSession;
    _loading = false;
  }

  Future<void> _requestBreak() async {
    if (_activeSession == null) return;
    await _breakService.requestBreak(_activeSession!.id, widget.childId);
    await _notificationService.insertNotification(
      parentId: _activeSession!.parentId,
      childId: widget.childId,
      type: 'break_requested',
      title: 'Break requested',
      body: '${widget.childName} wants a break',
    );
    setState(() => _breakRequested = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Break request sent to parent!')),
      );
    }
  }

  Future<void> _deleteTask(String taskId) async {
    await _proofService.deleteTask(taskId);
    await _checkActive();
  }

  int get _tasksRemaining => _tasks.where((t) => t.isPending).length;
  int get _tasksSubmitted => _tasks.where((t) => t.isSubmitted).length;
  bool get _allDone => _tasks.isNotEmpty && _tasksRemaining == 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.kidBg,
      appBar: AppBar(
        backgroundColor: AppColors.kidBg,
        foregroundColor: AppColors.kidInk,
        title: const SizedBox.shrink(),
      ),
      body: Stack(
        children: [
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: ShimmerCard(lines: 4),
                )
              : _activeSession == null
              ? _buildIdleState()
              : RefreshIndicator(
                  onRefresh: _checkActive,
                  child: _buildActiveState(context),
                ),
          if (_currentMilestone != null)
            MilestoneCelebration(
              milestone: _currentMilestone!,
              onDismiss: () => setState(() => _currentMilestone = null),
            ),
          if (_showSessionComplete)
            SessionCompleteCelebration(
              childName: widget.childName,
              tasksCompleted: _tasks.where((t) => !t.isPending).length,
              streakDays: _streak,
              onDismiss: () => setState(() => _showSessionComplete = false),
            ),
        ],
      ),
    );
  }

  /// "No homework lock right now" empty state. Big grass-toned
  /// check disc + two-line greeting. Kid-flavored, low-pressure.
  Widget _buildIdleState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.grass.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.checkCircle2,
              size: 60,
              color: AppColors.grass,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No homework lock right now',
            style: AppText.screenTitle(color: AppColors.kidInk),
          ),
          const SizedBox(height: 6),
          Text(
            'Enjoy your apps!',
            style: AppText.bodySecondary(),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _checkActive,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Refresh'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.kidInk,
              side: const BorderSide(color: AppColors.kidLine),
            ),
          ),
        ],
      ),
    );
  }

  /// Active-session layout: greeting block, big ring timer, task
  /// cards, footer actions. Mirrors the handoff's kid home where
  /// the ring dominates the screen and tasks live in a single
  /// card underneath.
  Widget _buildActiveState(BuildContext context) {
    // Compute progress inline so the kid-side ring ticks every
    // second without a full data refresh.
    final session = _activeSession!;
    final total = Duration(minutes: session.minLockMinutes);
    final elapsed = _now.difference(session.startedAt);
    final progress = total.inSeconds > 0
        ? (elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = total - elapsed;
    final clampedRemaining = remaining.isNegative
        ? Duration.zero
        : remaining;
    final remainingStr = clampedRemaining.inHours > 0
        ? '${clampedRemaining.inHours}h ${clampedRemaining.inMinutes.remainder(60)}m'
        : '${clampedRemaining.inMinutes.remainder(60)}:${clampedRemaining.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: 8,
      ),
      children: [
        // Greeting + streak chip
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FOCUS TIME',
                  style: AppText.eyebrow(color: AppColors.kidInk),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hey, ${widget.childName}',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.kidInk,
                  ),
                ),
              ],
            ),
            if (_streak > 0) _buildStreakChip(),
          ],
        ),
        const SizedBox(height: 24),
        // Big ring timer — kid variant (196px, grass progress, kid
        // track). Center digits are the remaining time; below the
        // ring is a small "until apps unlock" caption.
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              RingTimer.kid(
                progress: progress,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      remainingStr,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        height: 1.0,
                        color: AppColors.kidInk,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (session.isPaused)
                      Text(
                        'PAUSED',
                        style: AppText.eyebrow(color: AppColors.warn),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'until apps unlock',
            style: AppText.bodySecondary(),
          ),
        ),
        const SizedBox(height: 24),
        // Tasks card
        _buildTasksCard(context),
        if (_allDone) ...[
          const SizedBox(height: 12),
          _buildAllDoneCard(),
        ],
        if (_proofs.any((p) =>
            p.parentNote != null && p.parentNote!.isNotEmpty)) ...[
          const SizedBox(height: 12),
          _buildFeedbackCard(),
        ],
        const SizedBox(height: 16),
        // Footer actions: Add task (outline) + Break (ghost).
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TaskEntryScreen(
                      sessionId: session.id,
                      childName: widget.childName,
                    ),
                  ),
                ).then((_) => _checkActive()),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add task'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.kidInk,
                  side: const BorderSide(color: AppColors.kidLine),
                  backgroundColor: AppColors.card,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _breakRequested ? null : _requestBreak,
                icon: const Icon(LucideIcons.coffee, size: 16),
                label: Text(
                  _breakRequested ? 'Requested' : 'Ask for a Break',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.kidInk,
                  backgroundColor: AppColors.sageFill,
                  side: BorderSide.none,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => KidHistoryScreen(
                  childId: widget.childId,
                  childName: widget.childName,
                ),
              ),
            ),
            icon: const Icon(LucideIcons.history, size: 16),
            label: const Text('My history'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.kidInk,
            ),
          ),
        ),
      ],
    );
  }

  /// Streak chip — grass pill with flame icon. Shows the running
  /// streak; grace flag is surfaced as a small shield next to it
  /// so the kid (and parent) knows grace is helping.
  Widget _buildStreakChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warnFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warnBd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.flame,
            size: 16,
            color: AppColors.warnDot,
          ),
          const SizedBox(width: 6),
          Text(
            '$_streak day streak',
            style: AppText.listTitle(color: AppColors.warn),
          ),
          if (_streakGraceUsed) ...[
            const SizedBox(width: 6),
            const Icon(
              LucideIcons.shield,
              size: 12,
              color: AppColors.warn,
            ),
          ],
        ],
      ),
    );
  }

  /// Tasks card with kid-style rounded checkboxes. Pending = warm
  /// amber outline (#E0C88A); submitted = grass fill with check.
  /// Title strikes through when submitted.
  Widget _buildTasksCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.kidCard),
        border: Border.all(color: AppColors.kidLine),
      ),
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Today\'s tasks',
                style: AppText.cardHeader(color: AppColors.kidInk),
              ),
              const Spacer(),
              Text(
                '$_tasksSubmitted of ${_tasks.length} done',
                style: AppText.bodySecondary(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_tasks.isEmpty)
            Text(
              'Add what you need to finish today.',
              style: AppText.bodySecondary(),
            )
          else
            ...(_tasks.map(_buildTaskRow)),
          if (_tasks.isNotEmpty && !_allDone) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TaskEntryScreen(
                    sessionId: _activeSession!.id,
                    childName: widget.childName,
                  ),
                ),
              ).then((_) => _checkActive()),
              icon: const Icon(LucideIcons.camera, size: 16),
              label: const Text('Submit proof'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.grass,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskRow(HomeworkTask t) {
    final submitted = t.status != 'pending';
    return Dismissible(
      key: Key(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(AppRadius.iconTile),
        ),
        child: const Icon(LucideIcons.trash2, color: Colors.white, size: 18),
      ),
      onDismissed: (_) => _deleteTask(t.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 24px rounded checkbox: filled grass+check when done,
            // #E0C88A outline when pending.
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: submitted ? AppColors.grass : Colors.transparent,
                border: Border.all(
                  color: submitted ? AppColors.grass : const Color(0xFFE0C88A),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: submitted
                  ? const Icon(
                      LucideIcons.check,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.description,
                    style: AppText.body(
                      color: AppColors.kidInk,
                    ).copyWith(
                      decoration: submitted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    submitted ? 'Submitted' : 'Ready to submit',
                    style: AppText.bodySecondary(size: 11),
                  ),
                ],
              ),
            ),
            if (!submitted)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.grass,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TaskEntryScreen(
                        sessionId: _activeSession!.id,
                        childName: widget.childName,
                      ),
                    ),
                  ).then((_) => _checkActive()),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    'Proof',
                    style: AppText.button(color: Colors.white).copyWith(
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllDoneCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.okFill,
        borderRadius: BorderRadius.circular(AppRadius.kidCard),
        border: Border.all(color: const Color(0xFFB6D7BE)),
      ),
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.grass,
              borderRadius: BorderRadius.circular(AppRadius.iconTile),
            ),
            child: const Icon(
              LucideIcons.checkCircle2,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'All tasks submitted! Waiting for a parent to review.',
              style: AppText.body(color: AppColors.ok),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackCard() {
    final items = _proofs.where(
      (p) => p.parentNote != null && p.parentNote!.isNotEmpty,
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.infoFill,
        borderRadius: BorderRadius.circular(AppRadius.kidCard),
        border: Border.all(color: const Color(0xFFC8D8E0)),
      ),
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.messageSquare,
                size: 16,
                color: AppColors.info,
              ),
              const SizedBox(width: 6),
              Text(
                'Parent feedback',
                style: AppText.cardHeader(
                  color: AppColors.info,
                  size: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      p.isApproved
                          ? LucideIcons.checkCircle2
                          : LucideIcons.info,
                      size: 14,
                      color: p.isApproved
                          ? AppColors.ok
                          : AppColors.warnDot,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.parentNote!,
                        style: AppText.body(size: 12.5),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
