import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../services/break_service.dart';
import '../services/notification_service.dart';
import '../services/streak_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../widgets/ring_timer.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/milestone_celebration.dart';
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
    try {
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
            _breakRequested =
                sessionResults[2] != null &&
                (sessionResults[2] as BreakRequest).status == 'pending';
          });
        }
      }
      if (_hadActiveSession && newSession == null && _activeSession != null) {
        // Snapshot the values we need before clearing _activeSession
        // below — the new full-screen route captures them at push
        // time and the screen never re-reads from the kid home.
        final completedTasks = _tasks
            .where((t) => t.isSubmitted || t.isApproved)
            .length;
        final completedStreak = newStreak;
        // The session row's minLockMinutes is the minimum the parent
        // committed to; the kid's actual elapsed time would be more
        // honest but it isn't surfaced by SessionService.getActive.
        // Floor at 1 so the stat pill always reads "1 min" rather
        // than "0 min" for the (rare) zero-length auto-lifts.
        final completedMinutes = _activeSession?.minLockMinutes ?? 0;
        setState(() {
          _streak = newStreak;
          _streakGraceUsed = newStreakGraceUsed;
        });
        _previousStreak = newStreak;
        // Push the full-screen kid celebration. Replaces the legacy
        // SessionCompleteCelebration overlay so the kid gets a focused
        // moment without the home-screen chrome behind it.
        if (!mounted) return;
        Navigator.of(context).pushNamed(
          '/session-complete-kid',
          arguments: {
            'childName': widget.childName,
            'tasksCompleted': completedTasks,
            'streakDays': completedStreak,
            'minutesStudied': completedMinutes,
          },
        );
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
    } catch (e) {
      // Without this catch, a Supabase hiccup on the active-session
      // or task fetch leaves the kid staring at the loading spinner
      // forever. Surface the real exception so the kid (or parent)
      // can pull-to-refresh.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn’t load your homework: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestBreak() async {
    if (_activeSession == null) return;
    try {
      // Two independent inserts (break_request row + notifications row).
      // Run them in parallel so the kid sees the snackbar after one
      // round-trip's worth of latency, not two.
      await Future.wait([
        _breakService.requestBreak(_activeSession!.id, widget.childId),
        _notificationService.insertNotification(
          parentId: _activeSession!.parentId,
          childId: widget.childId,
          type: 'break_requested',
          title: 'Break requested',
          body: '${widget.childName} wants a break',
        ),
      ]);
      setState(() => _breakRequested = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Break request sent to parent!')),
        );
      }
    } catch (e) {
      // Without this catch, a Supabase hiccup would still leave
      // _breakRequested = false (no setState) but the kid would
      // never know why their parent didn't react. Surface the
      // failure so they know to try again.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t send break request: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _deleteTask(String taskId) async {
    try {
      await _proofService.deleteTask(taskId);
      await _checkActive();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t delete task: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  int get _tasksRemaining =>
      _tasks.where((t) => t.isPending || t.isRejected).length;
  int get _tasksSubmitted =>
      _tasks.where((t) => t.isSubmitted || t.isApproved).length;
  bool get _allDone => _tasks.isNotEmpty && _tasksRemaining == 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.screenPadding),
                    child: Column(
                      children: [
                        SizedBox(height: 8),
                        ShimmerCard(lines: 2),
                        SizedBox(height: 14),
                        ShimmerCard(lines: 3),
                        SizedBox(height: 14),
                        ShimmerCard(lines: 4),
                      ],
                    ),
                  )
                : _activeSession == null
                ? RefreshIndicator(
                    onRefresh: _checkActive,
                    color: AppColors.green,
                    child: _buildIdleState(),
                  )
                : RefreshIndicator(
                    onRefresh: _checkActive,
                    color: AppColors.green,
                    child: _buildActiveState(context),
                  ),
          ),
          if (_currentMilestone != null)
            MilestoneCelebration(
              milestone: _currentMilestone!,
              onDismiss: () => setState(() => _currentMilestone = null),
            ),
          // Session-complete celebration is no longer rendered as a
          // Stack overlay here — kid_home_screen now pushes the full-
          // screen /session-complete-kid route when the realtime
          // subscription reports an ended session. See _checkActive.
        ],
      ),
      bottomNavigationBar: _buildTabBar(),
    );
  }

  // ── Kid "Today" free-time state ──────────────────────────────────
  // Warm world, not a lockscreen jail. Apps are open; the greeting
  // celebrates the free time and the streak keeps momentum visible.
  Widget _buildIdleState() {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: 12,
      ),
      children: [
        _buildGreeting(
          eyebrow: 'KID · TODAY',
          greeting: 'Hi, ${widget.childName}',
        ),
        const SizedBox(height: 20),
        // "No session running / Apps open" hero — celebratory green.
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.greenTint,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: const Color(0xFFB6D7BE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.green,
                      borderRadius: BorderRadius.circular(AppRadius.iconTile),
                    ),
                    child: const Icon(
                      LucideIcons.checkCircle2,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No session running',
                          style: AppText.cardHeader(color: AppColors.greenDeep),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Apps open',
                          style: AppText.bodySecondary(color: AppColors.green),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Enjoy your free time',
                style: AppText.title(size: 20, color: AppColors.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'Your homework’s done for now. We’ll let you know when the '
                'next focus session starts.',
                style: AppText.body(size: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Streak keeps momentum visible even in free time.
        if (_streak > 0)
          DfCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.amberTint,
                    borderRadius: BorderRadius.circular(AppRadius.iconTile),
                  ),
                  child: const Icon(
                    LucideIcons.flame,
                    color: AppColors.amber,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_streak-day streak', style: AppText.cardHeader()),
                      Text(
                        _streakGraceUsed
                            ? 'A grace day is keeping it alive — nice save!'
                            : 'Keep it going. Finish today’s work to add a day.',
                        style: AppText.bodySecondary(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Active-session "Focus time" layout: greeting, streak, big
  /// countdown, reassurance, and today's work list. Warm palette —
  /// this is earning freedom, never a punishment screen.
  Widget _buildActiveState(BuildContext context) {
    // Compute progress inline so the countdown ticks every second
    // without a full data refresh.
    final session = _activeSession!;
    final total = Duration(minutes: session.minLockMinutes);
    final elapsed = _now.difference(session.startedAt);
    final progress = total.inSeconds > 0
        ? (elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = total - elapsed;
    final clampedRemaining = remaining.isNegative ? Duration.zero : remaining;
    final remainingStr = clampedRemaining.inHours > 0
        ? '${clampedRemaining.inHours}h ${clampedRemaining.inMinutes.remainder(60)}m'
        : '${clampedRemaining.inMinutes.remainder(60)}:${clampedRemaining.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: 12,
      ),
      children: [
        _buildGreeting(
          eyebrow: 'FOCUS TIME',
          greeting: 'Hey ${widget.childName}',
        ),
        const SizedBox(height: 20),
        // Countdown hero.
        _buildTimerHero(progress, remainingStr, session.isPaused),
        const SizedBox(height: 20),
        // Tasks card
        _buildTasksCard(context),
        if (_allDone) ...[const SizedBox(height: 12), _buildAllDoneCard()],
        if (_proofs.any(
          (p) => p.parentNote != null && p.parentNote!.isNotEmpty,
        )) ...[
          const SizedBox(height: 12),
          _buildFeedbackCard(),
        ],
        const SizedBox(height: 16),
        // Ask-for-a-break stays available but understated.
        Center(
          child: TextButton.icon(
            onPressed: _breakRequested ? null : _requestBreak,
            icon: const Icon(LucideIcons.coffee, size: 16),
            label: Text(
              _breakRequested ? 'Break requested' : 'Ask for a break',
            ),
            style: TextButton.styleFrom(foregroundColor: AppColors.ink70),
          ),
        ),
      ],
    );
  }

  /// Greeting block — mono eyebrow, big Bricolage hello, streak chip.
  Widget _buildGreeting({required String eyebrow, required String greeting}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow, style: AppText.eyebrow(color: AppColors.ink45)),
              const SizedBox(height: 6),
              Text(greeting, style: AppText.display(size: 30)),
            ],
          ),
        ),
        if (_streak > 0) ...[const SizedBox(width: 12), _buildStreakChip()],
      ],
    );
  }

  /// The big "until apps unlock" countdown. A grass ring frames the
  /// remaining time; the reassurance sits directly beneath.
  Widget _buildTimerHero(double progress, String remainingStr, bool paused) {
    return DfCard(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      child: Column(
        children: [
          RingTimer.kid(
            progress: progress,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  remainingStr,
                  style: AppText.bigTimer(size: 44, color: AppColors.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  paused ? 'PAUSED' : 'UNTIL APPS UNLOCK',
                  style: AppText.eyebrow(
                    color: paused ? AppColors.amber : AppColors.ink45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                LucideIcons.sparkles,
                size: 15,
                color: AppColors.green,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'Apps unlock the moment your work’s approved.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 13.5, color: AppColors.ink70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Streak chip — amber pill with flame icon. Grace flag surfaces as
  /// a small shield so the kid knows grace is helping.
  Widget _buildStreakChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.amberTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.amberTint2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.flame, size: 15, color: AppColors.amber),
          const SizedBox(width: 6),
          Text(
            '$_streak-day streak',
            style: AppText.caption(
              color: AppColors.amberDeep,
            ).copyWith(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          if (_streakGraceUsed) ...[
            const SizedBox(width: 6),
            const Icon(
              LucideIcons.shield,
              size: 12,
              color: AppColors.amberDeep,
            ),
          ],
        ],
      ),
    );
  }

  /// "Today's work" card (`done`/`total`) with kid-style status rows
  /// and an "Add proof" button.
  Widget _buildTasksCard(BuildContext context) {
    return DfCard(
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Today’s work', style: AppText.cardHeader()),
              const Spacer(),
              DfStatusPill(
                '$_tasksSubmitted/${_tasks.length}',
                tone: _allDone ? DfPillTone.success : DfPillTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Add what you need to finish today.',
                style: AppText.bodySecondary(),
              ),
            )
          else
            ...(_tasks.map(_buildTaskRow)),
          if (_tasks.isNotEmpty && !_allDone) ...[
            const SizedBox(height: 14),
            DfButton(
              'Add proof',
              icon: LucideIcons.camera,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TaskEntryScreen(
                    sessionId: _activeSession!.id,
                    childName: widget.childName,
                  ),
                ),
              ).then((_) => _checkActive()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskRow(HomeworkTask t) {
    final approved = t.isApproved;
    final submitted = t.isSubmitted;
    final rejected = t.isRejected;
    final done = approved || submitted;

    final String statusLabel = approved
        ? 'Approved'
        : submitted
        ? 'Checking…'
        : rejected
        ? 'Try again'
        : 'To do';

    final Color boxFill = approved
        ? AppColors.green
        : submitted
        ? AppColors.amber
        : rejected
        ? AppColors.dangerFg
        : Colors.transparent;
    final Color boxBorder = approved
        ? AppColors.green
        : submitted
        ? AppColors.amber
        : rejected
        ? AppColors.dangerFg
        : const Color(0xFFE0C88A);
    final Widget? boxIcon = approved
        ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
        : submitted
        ? const Icon(LucideIcons.clock, size: 13, color: Colors.white)
        : rejected
        ? const Icon(LucideIcons.rotateCcw, size: 13, color: Colors.white)
        : null;

    return Dismissible(
      key: Key(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(AppRadius.tile),
        ),
        child: const Icon(
          LucideIcons.trash2,
          color: AppColors.dangerFg,
          size: 18,
        ),
      ),
      onDismissed: (_) => _deleteTask(t.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: boxFill,
                border: Border.all(color: boxBorder, width: 1.6),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: boxIcon,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                t.description,
                style: AppText.listTitle().copyWith(
                  decoration: approved ? TextDecoration.lineThrough : null,
                  decorationColor: AppColors.ink45,
                  color: approved ? AppColors.ink45 : AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (done)
              DfStatusPill(
                statusLabel,
                tone: approved ? DfPillTone.success : DfPillTone.attention,
              )
            else
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TaskEntryScreen(
                      sessionId: _activeSession!.id,
                      childName: widget.childName,
                    ),
                  ),
                ).then((_) => _checkActive()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    rejected ? 'Retake' : 'Proof',
                    style: AppText.caption(
                      color: Colors.white,
                    ).copyWith(fontWeight: FontWeight.w700, fontSize: 12),
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
        color: AppColors.greenTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFFB6D7BE)),
      ),
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.green,
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
              'All done! Waiting for a parent to review — apps unlock the '
              'moment it’s approved.',
              style: AppText.body(size: 14, color: AppColors.greenDeep),
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
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
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
                color: AppColors.infoFg,
              ),
              const SizedBox(width: 6),
              Text(
                'Parent feedback',
                style: AppText.cardHeader(color: AppColors.infoFg, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    p.isApproved ? LucideIcons.checkCircle2 : LucideIcons.info,
                    size: 14,
                    color: p.isApproved ? AppColors.green : AppColors.amber,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(p.parentNote!, style: AppText.body(size: 12.5)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom tab bar — Today / Tasks / Progress / Me. Today is the
  /// current screen; the other tabs push the existing kid routes
  /// where the data to open them is available.
  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.borderCol)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            children: [
              _tabItem(LucideIcons.house, 'Today', active: true, onTap: null),
              _tabItem(
                LucideIcons.listChecks,
                'Tasks',
                onTap: _activeSession == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaskEntryScreen(
                            sessionId: _activeSession!.id,
                            childName: widget.childName,
                          ),
                        ),
                      ).then((_) => _checkActive()),
              ),
              _tabItem(
                LucideIcons.trendingUp,
                'Progress',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KidHistoryScreen(
                      childId: widget.childId,
                      childName: widget.childName,
                    ),
                  ),
                ),
              ),
              _tabItem(LucideIcons.user, 'Me', onTap: null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabItem(
    IconData icon,
    String label, {
    bool active = false,
    VoidCallback? onTap,
  }) {
    final color = active ? AppColors.green : AppColors.ink45;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppText.caption(color: color).copyWith(
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
