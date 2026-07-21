import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/models.dart';
import '../../services/break_service.dart';
import '../../services/proof_service.dart';
import '../../services/kid_realtime_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/subjects.dart';
import '../task_entry_screen.dart';
import '../proof_capture_screen.dart';

/// Shown when there's an active homework_sessions row with
/// status='active' for this kid device.
///
/// Big timer ticks down toward the session's natural end (computed
/// from started_at + min_lock_minutes). Task list with checkboxes,
/// inline add-task, and per-task proof submission via camera.
class LockedScreen extends StatefulWidget {
  final HomeworkSessionPayload session;
  final String childName;
  final VoidCallback onBreakRequestSent;

  const LockedScreen({
    super.key,
    required this.session,
    required this.childName,
    required this.onBreakRequestSent,
  });

  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen> {
  final _breakService = BreakService();
  final _proofService = ProofService();
  Timer? _tick;
  Timer? _refreshTimer;
  bool _sendingBreak = false;
  bool _breakSent = false;

  List<HomeworkTask> _tasks = [];
  List<ProofSubmission> _proofs = [];
  bool _loadingTasks = true;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadTasks(),
    );
    _loadTasks();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    try {
      final results = await Future.wait([
        _proofService.getTasks(widget.session.id),
        _proofService.getProofsForSession(widget.session.id),
      ]);
      if (mounted) {
        setState(() {
          _tasks = results[0] as List<HomeworkTask>;
          _proofs = results[1] as List<ProofSubmission>;
          _loadingTasks = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTasks = false);
    }
  }

  Future<void> _askForBreak() async {
    if (_sendingBreak || _breakSent) return;
    setState(() => _sendingBreak = true);
    try {
      await _breakService.requestBreak(
        widget.session.id,
        widget.session.childId,
      );
      if (!mounted) return;
      setState(() {
        _breakSent = true;
        _sendingBreak = false;
      });
      widget.onBreakRequestSent();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingBreak = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send break request: $e')),
      );
    }
  }

  Future<void> _deleteTask(String taskId) async {
    try {
      await _proofService.deleteTask(taskId);
      await _loadTasks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t delete task: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Duration get _remaining {
    final endsAt = widget.session.startedAt.add(
      Duration(minutes: widget.session.minLockMinutes),
    );
    final now = DateTime.now();
    final diff = endsAt.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  int get _tasksRemaining => _tasks.where((t) => t.isPending).length;
  int get _tasksSubmitted => _tasks.where((t) => !t.isPending).length;
  bool get _allDone => _tasks.isNotEmpty && _tasksRemaining == 0;

  void _showAddTaskDialog() {
    final controller = TextEditingController();
    String selectedSubject = kDefaultSubject;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add homework task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'What needs to be done?',
                  hintText: 'e.g. Math worksheet page 12',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedSubject,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  prefixIcon: Icon(LucideIcons.bookOpen, size: 18),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                isExpanded: true,
                items: kSubjects
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, style: const TextStyle(fontSize: 14)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedSubject = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final desc = controller.text.trim();
                if (desc.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await _proofService.addTask(
                    widget.session.id,
                    desc,
                    subject: selectedSubject,
                  );
                  await _loadTasks();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Couldn\'t add task: $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    ).then((_) => controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final session = widget.session;
    final total = Duration(minutes: session.minLockMinutes);
    final elapsed = _now.difference(session.startedAt);
    final progress = total.inSeconds > 0
        ? (elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0)
        : 0.0;
    final clampedRemaining = remaining.isNegative
        ? Duration.zero
        : remaining;
    final remainingStr = clampedRemaining.inHours > 0
        ? '${clampedRemaining.inHours}h ${clampedRemaining.inMinutes.remainder(60)}m'
        : '${clampedRemaining.inMinutes.remainder(60)}:${clampedRemaining.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppColors.kidBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
            vertical: 8,
          ),
          children: [
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
              ],
            ),
            const SizedBox(height: 24),
            // Timer ring
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 10,
                      backgroundColor: AppColors.kidLine,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.grass,
                      ),
                    ),
                  ),
                  Column(
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
                        ),
                      ),
                    ],
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
            _buildTasksCard(),
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
            // Footer actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showAddTaskDialog,
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
                    onPressed: _breakSent ? null : (_sendingBreak ? null : _askForBreak),
                    icon: _sendingBreak
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.kidInk,
                            ),
                          )
                        : const Icon(LucideIcons.coffee, size: 16),
                    label: Text(
                      _breakSent ? 'Sent' : 'Ask for a Break',
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksCard() {
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
          if (_loadingTasks)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_tasks.isEmpty)
            Text(
              'Add what you need to finish today.',
              style: AppText.bodySecondary(),
            )
          else
            ...(_tasks.map(_buildTaskRow)),
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
                    submitted ? 'Submitted' : t.subject,
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
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProofCaptureScreen(
                        taskId: t.id,
                        taskDescription: t.description,
                      ),
                    ),
                  ).then((_) => _loadTasks()),
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
