import 'dart:async';
import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../services/break_service.dart';
import '../theme/app_theme.dart';
import '../widgets/session_timer.dart';
import 'task_entry_screen.dart';

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
  Map<String, dynamic>? _activeSession;
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  Timer? _refreshTimer;
  bool _breakRequested = false;

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
    final sessions = await _sessionService.getActiveSession(widget.childId);
    if (!mounted) return;
    setState(() {
      _activeSession = sessions.isNotEmpty ? sessions.first : null;
    });
    if (_activeSession != null) {
      final tasks = await _proofService.getTasks(_activeSession!['id']);
      if (mounted) setState(() => _tasks = tasks);
    }
    _loading = false;
  }

  Future<void> _requestBreak() async {
    if (_activeSession == null) return;
    await _breakService.requestBreak(_activeSession!['id'], widget.childId);
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

  int get _tasksRemaining =>
      _tasks.where((t) => t['status'] == 'pending').length;
  int get _tasksSubmitted =>
      _tasks.where((t) => t['status'] == 'submitted').length;
  bool get _allDone => _tasks.isNotEmpty && _tasksRemaining == 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Hi, ${widget.childName}')),
      body: _loading
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
                  SessionTimer(
                    sessionStart: DateTime.parse(_activeSession!['started_at']),
                    durationMinutes: _activeSession!['min_lock_minutes'] ?? 60,
                    minUnlockMinutes: _activeSession!['min_lock_minutes'],
                    autoLiftMinutes: _activeSession!['max_lift_minutes'],
                    paused: _activeSession!['status'] == 'paused',
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
                                    sessionId: _activeSession!['id'],
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
                                key: Key(t['id']),
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
                                onDismissed: (_) => _deleteTask(t['id']),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(
                                      t['status'] != 'pending'
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: t['status'] != 'pending'
                                          ? AppColors.success
                                          : AppColors.accent,
                                      size: 20,
                                    ),
                                    title: Text(
                                      t['description'] ?? '',
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    trailing: t['status'] == 'pending'
                                        ? TextButton(
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => TaskEntryScreen(
                                                  sessionId:
                                                      _activeSession!['id'],
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
                            sessionId: _activeSession!['id'],
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
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _breakRequested ? null : _requestBreak,
                    icon: const Icon(Icons.coffee),
                    label: Text(
                      _breakRequested ? 'Break Requested' : 'Ask for a Break',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
