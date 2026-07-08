import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../services/break_service.dart';
import '../services/notification_service.dart';
import '../services/streak_service.dart';
import '../theme/app_theme.dart';
import '../widgets/session_timer.dart';
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
  int _previousStreak = 0;
  HomeworkSession? _activeSession;
  List<HomeworkTask> _tasks = [];
  List<ProofSubmission> _proofs = [];
  bool _loading = true;
  Timer? _refreshTimer;
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
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkActive() async {
    final newSession =
        await _sessionService.getActiveSession(widget.childId);
    if (!mounted) return;
    if (newSession != null) {
      final tasks = await _proofService.getTasks(newSession!.id);
      final proofs = await _proofService.getProofsForSession(newSession!.id);
      if (mounted) setState(() {
        _tasks = tasks;
        _proofs = proofs;
      });
    }
    if (_hadActiveSession && newSession == null && _activeSession != null) {
      final tasksCompleted = _tasks.where((t) => !t.isPending).length;
      final newStreak = await _streakService.computeStreak(widget.childId);
      setState(() {
        _showSessionComplete = true;
        _streak = newStreak;
      });
      _previousStreak = newStreak;
    } else {
      final newStreak = await _streakService.computeStreak(widget.childId);
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
      _streak = newStreak;
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
      appBar: AppBar(title: Text('Hi, ${widget.childName}')),
      body: Stack(
        children: [
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: ShimmerCard(lines: 4),
                )
          ? const Center(child: CircularProgressIndicator())
          : _activeSession == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 56,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No homework lock right now',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enjoy your apps!',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _checkActive,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_streak > 0)
                    Card(
                      color: AppColors.accent.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Text(
                              _streak >= 7 ? '🔥' : '⭐',
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$_streak-day streak!',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.accent,
                              ),
                            ),
                            if (_streak >= 7)
                              const Text(
                                ' Unstoppable!',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  SessionTimer(
                    sessionStart: _activeSession!.startedAt,
                    durationMinutes: _activeSession!.minLockMinutes,
                    minUnlockMinutes: _activeSession!.minLockMinutes,
                    autoLiftMinutes: _activeSession!.maxLiftMinutes,
                    paused: _activeSession!.isPaused,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.assignment,
                                size: 20,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Tasks ($_tasksSubmitted/${_tasks.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          if (_tasks.isEmpty) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Add what you need to finish today',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
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
                              icon: const Icon(Icons.add),
                              label: const Text('Add Tasks'),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            ...(_tasks.map(
                              (t) => Dismissible(
                                key: Key(t.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                  ),
                                ),
                                onDismissed: (_) => _deleteTask(t.id),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(
                                      t.status != 'pending'
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: t.status != 'pending'
                                          ? AppColors.success
                                          : AppColors.accent,
                                      size: 20,
                                    ),
                                    title: Text(
                                      t.description,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    trailing: t.status == 'pending'
                                        ? TextButton(
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => TaskEntryScreen(
                                                  sessionId:
                                                      _activeSession!.id,
                                                  childName: widget.childName,
                                                ),
                                              ),
                                            ).then((_) => _checkActive()),
                                            child: const Text('Submit'),
                                          )
                                        : Text(
                                            'Submitted',
                                            style: TextStyle(
                                              color: AppColors.success,
                                              fontSize: 12,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            )),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_tasks.isNotEmpty && !_allDone) ...[
                    const SizedBox(height: 12),
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
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Submit Proof'),
                    ),
                  ],
                  if (_allDone) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: AppColors.success.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'All tasks submitted! Waiting for parent to review.',
                                style: TextStyle(
                                  color: AppColors.success.withOpacity(0.9),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_proofs.any((p) => p.parentNote != null && p.parentNote!.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: AppColors.info.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.feedback, size: 18, color: AppColors.info),
                                SizedBox(width: 6),
                                Text(
                                  'Parent Feedback',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.info,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._proofs
                              .where((p) => p.parentNote != null && p.parentNote!.isNotEmpty)
                              .map((p) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      p.isApproved ? Icons.check_circle : Icons.info,
                                      size: 14,
                                      color: p.isApproved ? AppColors.success : AppColors.accent,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        p.parentNote!,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _breakRequested ? null : _requestBreak,
                    icon: const Icon(Icons.coffee),
                    label: Text(
                      _breakRequested ? 'Break Requested' : 'Ask for a Break',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => KidHistoryScreen(
                          childId: widget.childId,
                          childName: widget.childName,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('My History'),
                  ),
                ],
              ),
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
}
