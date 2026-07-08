import 'package:flutter/material.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
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
  String _selectedSubject = 'General';
  List<HomeworkTask> _tasks = [];

  static const List<String> subjects = [
    'General',
    'Math',
    'Science',
    'English',
    'History',
    'Foreign Language',
    'Art',
    'Music',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final tasks = await _proofService.getTasks(widget.sessionId);
    setState(() => _tasks = tasks);
  }

  Future<void> _addTask() async {
    final desc = _controller.text.trim();
    if (desc.isEmpty) return;
    await _proofService.addTask(
      widget.sessionId,
      desc,
      subject: _selectedSubject,
    );
    _controller.clear();
    await _loadTasks();
  }

  Future<void> _deleteTask(String taskId) async {
    await _proofService.deleteTask(taskId);
    await _loadTasks();
  }

  Future<void> _retakeProof(String taskId, String description) async {
    // Delete old proof if exists
    final oldProof = await _proofService.getLatestProof(taskId);
    if (oldProof != null) {
      await _proofService.deleteProof(oldProof!.id);
    }
    // Reset task status to pending
    await _proofService.deleteTask(taskId);
    await _proofService.addTask(widget.sessionId, description);
    await _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Today\'s Homework')),
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
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedSubject,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    prefixIcon: Icon(Icons.book, size: 20),
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
                            color: AppColors.primary.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_note,
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
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _deleteTask(taskId),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              isDone
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
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
                                    icon: const Icon(Icons.refresh, size: 20),
                                    tooltip: 'Retake',
                                    onPressed: () =>
                                        _retakeProof(taskId, description),
                                  )
                                else ...[
                                  FilledButton(
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
                                    child: const Text('Submit Proof'),
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
