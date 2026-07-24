import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../models/models.dart';
import '../utils/subjects.dart';
import 'proof_capture_screen.dart';

class TaskEntryScreen extends StatefulWidget {
  final String sessionId;
  final String childName;
  const TaskEntryScreen({
    super.key,
    required this.sessionId,
    required this.childName,
  });

  @override
  State<TaskEntryScreen> createState() => _TaskEntryScreenState();
}

class _TaskEntryScreenState extends State<TaskEntryScreen> {
  final _proofService = ProofService();
  final _controller = TextEditingController();
  String _selectedSubject = kDefaultSubject;
  List<HomeworkTask> _tasks = [];

  static const List<String> subjects = kSubjects;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final tasks = await _proofService.getTasks(widget.sessionId);
      if (!mounted) return;
      setState(() => _tasks = tasks);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t load tasks: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _addTask() async {
    final desc = _controller.text.trim();
    if (desc.isEmpty) return;
    try {
      await _proofService.addTask(
        widget.sessionId,
        desc,
        subject: _selectedSubject,
      );
      _controller.clear();
      await _loadTasks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t add task: $e'),
          backgroundColor: AppColors.danger,
        ),
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
          content: Text('Couldn’t delete task: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _retakeProof(String taskId, String description) async {
    // Retake flow: replace the existing task with a fresh one.
    //
    // The previous version did deleteTask() then addTask() — if the
    // add failed, the kid was left with no task at all (bug audit
    // pattern #9). Reordered so the add runs first; on failure the
    // old task is still there, at worst a brief duplicate.
    try {
      await _proofService.addTask(widget.sessionId, description);
      final oldProof = await _proofService.getLatestProof(taskId);
      if (oldProof != null) {
        await _proofService.deleteProof(oldProof.id);
      }
      await _proofService.deleteTask(taskId);
      await _loadTasks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t retake proof: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  int get _doneCount =>
      _tasks.where((t) => t.isSubmitted || t.isApproved).length;
  int get _remainingCount =>
      _tasks.where((t) => t.isPending || t.isRejected).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Text('Tasks', style: AppText.screenTitle()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.screenPadding),
            child: Center(
              child: DfStatusPill(
                'Focusing',
                tone: DfPillTone.success,
                dot: true,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: 12,
        ),
        children: [
          _buildProgressCard(),
          const SizedBox(height: AppSpacing.blockGap),
          _buildAddTaskCard(),
          const SizedBox(height: AppSpacing.blockGap),
          if (_tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: DfEmptyState(
                icon: LucideIcons.listChecks,
                title: 'No tasks yet',
                hint:
                    'Add what you need to finish today, then snap a photo '
                    'of each one when it’s done.',
              ),
            )
          else ...[
            ..._tasks.map(_buildTaskCard),
            const SizedBox(height: 8),
            _buildFooterNudge(),
          ],
        ],
      ),
    );
  }

  /// "Today's tasks" (`done`/`total`) with a progress bar.
  Widget _buildProgressCard() {
    final total = _tasks.length;
    final frac = total == 0 ? 0.0 : (_doneCount / total).clamp(0.0, 1.0);
    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Today’s tasks', style: AppText.cardHeader()),
              const Spacer(),
              Text(
                '$_doneCount / $total',
                style: AppText.statValue(size: 20, color: AppColors.green),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : frac,
              minHeight: 10,
              backgroundColor: AppColors.border2,
              valueColor: const AlwaysStoppedAnimation(AppColors.green),
            ),
          ),
        ],
      ),
    );
  }

  /// Add-a-task input + subject selector. Kept so the kid can still
  /// build out their list; wired to ProofService.addTask.
  Widget _buildAddTaskCard() {
    return DfCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Add a task — e.g. Math worksheet',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addTask(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _addTask,
                icon: const Icon(LucideIcons.plus, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedSubject,
            decoration: const InputDecoration(
              prefixIcon: Icon(LucideIcons.bookOpen, size: 18),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            isExpanded: true,
            items: subjects
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, style: AppText.body(size: 14)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedSubject = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(HomeworkTask task) {
    final taskId = task.id;
    final description = task.description;
    final subject = task.subject;
    final approved = task.isApproved;
    final submitted = task.isSubmitted;
    final rejected = task.isRejected;
    final done = approved || submitted;

    final String statusLabel = approved
        ? 'Approved'
        : submitted
        ? 'Checking your photo…'
        : rejected
        ? 'Needs a clearer photo'
        : 'Not started yet';
    final DfPillTone statusTone = approved
        ? DfPillTone.success
        : submitted
        ? DfPillTone.attention
        : rejected
        ? DfPillTone.danger
        : DfPillTone.neutral;
    final IconData leadIcon = approved
        ? LucideIcons.checkCircle2
        : submitted
        ? LucideIcons.clock
        : rejected
        ? LucideIcons.rotateCcw
        : LucideIcons.circle;
    final Color leadColor = approved
        ? AppColors.green
        : submitted
        ? AppColors.amber
        : rejected
        ? AppColors.dangerFg
        : AppColors.ink45;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: Key(taskId),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: AppColors.dangerBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: const Icon(
            LucideIcons.trash2,
            color: AppColors.dangerFg,
            size: 18,
          ),
        ),
        onDismissed: (_) => _deleteTask(taskId),
        child: DfCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(leadIcon, size: 22, color: leadColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          description,
                          style: AppText.listTitle().copyWith(
                            decoration: approved
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: AppColors.ink45,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(subject, style: AppText.bodySecondary(size: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (done)
                    IconButton(
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      tooltip: 'Retake',
                      color: AppColors.ink45,
                      onPressed: () => _retakeProof(taskId, description),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  DfStatusPill(statusLabel, tone: statusTone),
                  const Spacer(),
                  if (!done)
                    DfButton(
                      rejected ? 'Retake proof' : 'Add proof',
                      icon: LucideIcons.camera,
                      expand: false,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProofCaptureScreen(
                              taskId: taskId,
                              taskDescription: description,
                              taskSubject: subject,
                            ),
                          ),
                        ).then((_) => _loadTasks());
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Footer nudge — "Finish the last one to unlock" when work remains,
  /// or a celebratory line once everything's in.
  Widget _buildFooterNudge() {
    final remaining = _remainingCount;
    if (remaining == 0) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.greenTint,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: const Color(0xFFB6D7BE)),
        ),
        child: Row(
          children: [
            const Icon(
              LucideIcons.partyPopper,
              color: AppColors.green,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'All your work’s in! Apps unlock the moment it’s approved.',
                style: AppText.body(size: 14, color: AppColors.greenDeep),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.amberTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.amberTint2),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.sparkles, color: AppColors.amber, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  remaining == 1
                      ? 'Finish the last one to unlock'
                      : 'Finish your tasks to unlock',
                  style: AppText.cardHeader(
                    size: 15,
                    color: AppColors.amberDeep,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  remaining == 1
                      ? '1 task left. Snap it and you’re free.'
                      : '$remaining tasks left. Snap them and you’re free.',
                  style: AppText.bodySecondary(color: AppColors.amberDeep),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
