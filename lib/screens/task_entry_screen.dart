import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Today\'s homework', style: AppText.screenTitle()),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          labelText: 'Add a task',
                          hintText: 'e.g. Math worksheet',
                        ),
                        onSubmitted: (_) => _addTask(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _addTask,
                      icon: const Icon(LucideIcons.plus, size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSubject,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    prefixIcon: Icon(LucideIcons.bookOpen, size: 18),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  isExpanded: true,
                  items: subjects
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, style: const TextStyle(fontSize: 14)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedSubject = v);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _tasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha:0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.pencil,
                            size: 40,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Add what you need to finish today',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Type above and press +',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _tasks.length,
                    itemBuilder: (ctx, i) {
                      final task = _tasks[i];
                      final taskId = task.id;
                      final description = task.description;
                      final subject = task.subject;
                      final isDone = task.status != 'pending';
                      final taskStatus = task.status;

                      return Dismissible(
                        key: Key(taskId),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(LucideIcons.trash2, color: Colors.white, size: 18),
                        ),
                        onDismissed: (_) => _deleteTask(taskId),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              isDone
                                  ? LucideIcons.checkCircle2
                                  : LucideIcons.circle,
                              color: isDone
                                  ? AppColors.success
                                  : AppColors.accent,
                            ),
                            title: Text(
                              description,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '$subject · Status: $taskStatus',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isDone)
                                  IconButton(
                                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                                    tooltip: 'Retake',
                                    onPressed: () =>
                                        _retakeProof(taskId, description),
                                  )
                                else ...[
                                  FilledButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ProofCaptureScreen(
                                            taskId: taskId,
                                            taskDescription: description,
                                          ),
                                        ),
                                      ).then((_) => _loadTasks());
                                    },
                                    icon: const Icon(LucideIcons.camera, size: 16),
                                    label: const Text('Proof'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.grass,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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
