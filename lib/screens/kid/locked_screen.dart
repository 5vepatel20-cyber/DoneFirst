import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/models.dart';
import '../../services/break_service.dart';
import '../../services/proof_service.dart';
import '../../services/kid_realtime_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/subjects.dart';
import '../../widgets/df_kit.dart';
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

  int get _tasksRemaining =>
      _tasks.where((t) => t.isPending || t.isRejected).length;
  int get _tasksSubmitted =>
      _tasks.where((t) => !t.isPending && !t.isRejected).length;
  bool get _allDone => _tasks.isNotEmpty && _tasksRemaining == 0;

  /// True when a proof has been submitted for this task but no
  /// approval has landed yet — the "Checking your photo…" state.
  bool _isChecking(HomeworkTask t) {
    if (t.isApproved || t.isSubmitted) return false;
    return _proofs.any((p) => p.taskId == t.id && !p.isApproved);
  }

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
    final clampedRemaining = remaining.isNegative ? Duration.zero : remaining;
    final remainingStr = clampedRemaining.inHours > 0
        ? '${clampedRemaining.inHours}h ${clampedRemaining.inMinutes.remainder(60)}m'
        : '${clampedRemaining.inMinutes.remainder(60)}:${clampedRemaining.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            12,
            AppSpacing.screenPadding,
            28,
          ),
          children: [
            // ── Greeting header ───────────────────────────────────
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.greenTint,
                    borderRadius: BorderRadius.circular(AppRadius.iconTile),
                  ),
                  child: const Icon(
                    LucideIcons.sprout,
                    size: 22,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FOCUS TIME',
                        style: AppText.eyebrow(color: AppColors.green),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Hey ${widget.childName}',
                        style: AppText.title(size: 24),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            // ── Countdown ring ────────────────────────────────────
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 186,
                    height: 186,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      backgroundColor: AppColors.greenTint,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.green,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        remainingStr,
                        style: AppText.bigTimer(size: 46, color: AppColors.ink),
                      ),
                      const SizedBox(height: 4),
                      Text('until apps unlock', style: AppText.bodySecondary()),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                'Apps unlock the moment your work\'s approved.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 14),
              ),
            ),
            const SizedBox(height: 24),
            // ── Tasks ─────────────────────────────────────────────
            _buildTasksCard(),
            if (_allDone) ...[const SizedBox(height: 12), _buildAllDoneCard()],
            if (_proofs.any(
              (p) => p.parentNote != null && p.parentNote!.isNotEmpty,
            )) ...[
              const SizedBox(height: 12),
              _buildFeedbackCard(),
            ],
            const SizedBox(height: 20),
            // ── Footer actions ────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: DfButton(
                    'Add task',
                    icon: LucideIcons.plus,
                    variant: DfButtonVariant.outline,
                    onPressed: _showAddTaskDialog,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DfButton(
                    _breakSent ? 'Break sent' : 'Ask for a break',
                    icon: LucideIcons.coffee,
                    variant: DfButtonVariant.amber,
                    loading: _sendingBreak,
                    onPressed: (_breakSent || _sendingBreak)
                        ? null
                        : _askForBreak,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksCard() {
    return DfCard(
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Today's work", style: AppText.cardHeader(size: 17)),
              const Spacer(),
              DfStatusPill(
                '$_tasksSubmitted / ${_tasks.length}',
                tone: _allDone ? DfPillTone.success : DfPillTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingTasks)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.green,
                  ),
                ),
              ),
            )
          else if (_tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Add what you need to finish today, then snap a photo '
                'to prove it.',
                style: AppText.bodySecondary(),
              ),
            )
          else
            ...(_tasks.map(_buildTaskRow)),
        ],
      ),
    );
  }

  Widget _buildTaskRow(HomeworkTask t) {
    final approved = t.isApproved || t.isSubmitted;
    final rejected = t.isRejected;
    final checking = _isChecking(t);

    final Color boxFill;
    final Color boxBorder;
    final Widget? boxIcon;
    if (approved) {
      boxFill = AppColors.green;
      boxBorder = AppColors.green;
      boxIcon = const Icon(LucideIcons.check, size: 15, color: Colors.white);
    } else if (rejected) {
      boxFill = AppColors.dangerFg;
      boxBorder = AppColors.dangerFg;
      boxIcon = const Icon(LucideIcons.x, size: 15, color: Colors.white);
    } else if (checking) {
      boxFill = AppColors.amberTint;
      boxBorder = AppColors.amber;
      boxIcon = null;
    } else {
      boxFill = Colors.transparent;
      boxBorder = AppColors.borderCol;
      boxIcon = null;
    }

    final String statusLine;
    Color? statusColor;
    if (approved) {
      statusLine = 'Done';
      statusColor = AppColors.green;
    } else if (rejected) {
      statusLine = 'Have another go — snap it again';
      statusColor = AppColors.dangerFg;
    } else if (checking) {
      statusLine = 'Checking your photo…';
      statusColor = AppColors.amberDeep;
    } else {
      statusLine = t.subject;
      statusColor = null;
    }

    return Dismissible(
      key: Key(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.dangerFg,
          borderRadius: BorderRadius.circular(AppRadius.tile),
        ),
        child: const Icon(LucideIcons.trash2, color: Colors.white, size: 18),
      ),
      onDismissed: (_) => _deleteTask(t.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.description,
                    style: AppText.listTitle(size: 15).copyWith(
                      decoration: approved
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: AppColors.ink45,
                      color: approved ? AppColors.ink45 : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusLine,
                    style: AppText.bodySecondary(size: 12, color: statusColor),
                  ),
                ],
              ),
            ),
            if (!approved && !checking)
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProofCaptureScreen(
                      taskId: t.id,
                      taskDescription: t.description,
                      taskSubject: t.subject,
                    ),
                  ),
                ).then((_) => _loadTasks()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.camera,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Add proof',
                        style: AppText.button(color: Colors.white, size: 13),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllDoneCard() {
    return DfCard(
      color: AppColors.greenTint,
      borderColor: AppColors.green.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(AppRadius.iconTile),
            ),
            child: const Icon(
              LucideIcons.partyPopper,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'All done — nice work! Waiting on a parent to give the '
              'final nod.',
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
    return DfCard(
      color: AppColors.infoBg,
      borderColor: AppColors.infoFg.withValues(alpha: 0.22),
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
              const SizedBox(width: 8),
              Text(
                'Parent feedback',
                style: AppText.cardHeader(color: AppColors.infoFg, size: 15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    p.isApproved
                        ? LucideIcons.circleCheckBig
                        : LucideIcons.info,
                    size: 15,
                    color: p.isApproved ? AppColors.green : AppColors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.parentNote!, style: AppText.body(size: 13)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
