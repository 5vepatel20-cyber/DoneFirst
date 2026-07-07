import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../services/blocking_service.dart';
import '../services/break_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/session_timer.dart';
import 'proof_image_viewer.dart';

class LockActiveScreen extends StatefulWidget {
  final String sessionId;
  final String childName;
  const LockActiveScreen({
    super.key,
    required this.sessionId,
    required this.childName,
  });

  @override
  State<LockActiveScreen> createState() => _LockActiveScreenState();
}

class _LockActiveScreenState extends State<LockActiveScreen> {
  final _auth = AuthService();
  final _sessionService = SessionService();
  final _proofService = ProofService();
  final _blockingService = BlockingService();
  final _breakService = BreakService();
  final _notificationService = NotificationService();
  List<Map<String, dynamic>> _proofs = [];
  List<Map<String, dynamic>> _breakRequests = [];
  Map<String, dynamic>? _session;
  bool _loading = true;
  bool _paused = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadAll(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final sessions = await _sessionService.getSessionById(widget.sessionId);
    final proofs = await _proofService.getProofsForSession(widget.sessionId);
    final breaks = await _breakService.getPendingBreaks(widget.sessionId);
    if (mounted)
      setState(() {
        _session = sessions;
        _proofs = proofs;
        _breakRequests = breaks;
        _paused = sessions?['status'] == 'paused';
        _loading = false;
      });
    await _checkAutoUnlock();
  }

  Future<void> _extendSession() async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Extend Lock'),
        content: const Text('Add extra minutes to this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 15),
            child: const Text('+15 min'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 30),
            child: const Text('+30 min'),
          ),
        ],
      ),
    );
    if (minutes != null && minutes > 0) {
      await _sessionService.extendSession(widget.sessionId, minutes);
      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lock extended by $minutes minutes')),
        );
      }
    }
  }

  Future<void> _checkAutoUnlock() async {
    if (_proofs.isEmpty) return;
    final allDecided = _proofs.every((p) => p['parent_decision'] != 'pending');
    if (allDecided) {
      final allApproved = _proofs.every(
        (p) => p['parent_decision'] == 'approved',
      );
      if (allApproved) await _unlock();
    }
  }

  Future<void> _togglePause() async {
    if (_paused) {
      await _sessionService.resumeSession(widget.sessionId);
      await _blockingService.startBlocking();
    } else {
      await _sessionService.pauseSession(widget.sessionId);
      await _blockingService.stopBlocking();
    }
    await _loadAll();
  }

  Future<void> _unlock() async {
    await _blockingService.stopBlocking();
    await _sessionService.endSession(widget.sessionId);
    if (_session != null) {
      final parentId =
          _session!['parent_id'] as String? ?? _auth.currentUser!.id;
      await _notificationService.insertNotification(
        parentId: parentId,
        childId: _session!['child_id'] as String?,
        type: 'session_complete',
        title: 'Session complete',
        body: '${widget.childName} finished homework',
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apps unlocked! Homework complete.')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _handleDecision(
    String proofId,
    String decision, {
    String? note,
  }) async {
    await _proofService.updateParentDecision(
      proofId,
      decision,
      parentNote: note,
    );
    await _loadAll();
  }

  Future<void> _promptDecision(String proofId, String decision) async {
    if (decision == 'approved') {
      await _handleDecision(proofId, decision);
      return;
    }
    final noteController = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reason for rejection'),
        content: TextField(
          controller: noteController,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Tell your child what to fix...',
            labelText: 'Note (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, noteController.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    await _handleDecision(proofId, decision, note: note);
  }

  Future<void> _handleBreak(String breakId, String decision) async {
    await _breakService.respondToBreak(breakId, decision);
    if (decision == 'approved') {
      await _blockingService.stopBlocking();
      await Future.delayed(const Duration(minutes: 5));
      await _blockingService.startBlocking();
    }
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName} — Lock Active'),
        actions: [
          TextButton(onPressed: _unlock, child: const Text('Unlock Early')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_session != null)
                    SessionTimer(
                      sessionStart: DateTime.parse(_session!['started_at']),
                      durationMinutes: _session!['min_lock_minutes'] ?? 60,
                      minUnlockMinutes: _session!['min_lock_minutes'],
                      autoLiftMinutes: _session!['max_lift_minutes'],
                      paused: _paused,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _togglePause,
                          icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                          label: Text(_paused ? 'Resume' : 'Pause'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _extendSession,
                          icon: const Icon(Icons.timer_outlined),
                          label: const Text('Extend'),
                        ),
                      ),
                    ],
                  ),
                  if (_breakRequests.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: AppColors.info.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Break Requests',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            ..._breakRequests.map(
                              (br) => Row(
                                children: [
                                  const Expanded(
                                    child: Text('Child wants a break'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        _handleBreak(br['id'], 'approved'),
                                    child: const Text(
                                      'Allow',
                                      style: TextStyle(
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        _handleBreak(br['id'], 'rejected'),
                                    child: const Text(
                                      'Deny',
                                      style: TextStyle(color: AppColors.danger),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_proofs.any(
                    (p) => p['parent_decision'] == 'pending',
                  )) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          for (final p in _proofs) {
                            if (p['parent_decision'] == 'pending') {
                              await _proofService.updateParentDecision(
                                p['id'],
                                'approved',
                              );
                            }
                          }
                          if (_session != null) {
                            final parentId =
                                _session!['parent_id'] as String? ??
                                _auth.currentUser!.id;
                            await _notificationService.insertNotification(
                              parentId: parentId,
                              childId: _session!['child_id'] as String?,
                              type: 'proof_submitted',
                              title: 'All proofs approved',
                              body:
                                  '${widget.childName}\'s homework all approved',
                            );
                          }
                          await _loadAll();
                        },
                        icon: const Icon(Icons.done_all),
                        label: const Text('Approve All'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_proofs.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.hourglass_empty,
                              size: 48,
                              color: AppColors.accent,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Waiting for proof submissions...',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Auto-refreshes every 10s',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._proofs.map((proof) => _buildProofCard(proof)),
                ],
              ),
            ),
    );
  }

  Widget _buildProofCard(Map<String, dynamic> proof) {
    final taskDesc = proof['task_description'] ?? 'Task';
    final aiDecision = proof['ai_decision'] ?? 'pending';
    final parentDecision = proof['parent_decision'] ?? 'pending';
    final imageUrl = proof['image_url'] ?? '';

    final aiColor = aiDecision == 'approved'
        ? AppColors.success
        : aiDecision == 'rejected'
        ? AppColors.danger
        : AppColors.accent;
    final parentColor = parentDecision == 'approved'
        ? AppColors.success
        : parentDecision == 'rejected'
        ? AppColors.danger
        : AppColors.textSecondary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    taskDesc,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (parentDecision != 'pending')
                  Icon(
                    parentDecision == 'approved'
                        ? Icons.check_circle
                        : Icons.cancel,
                    color: parentColor,
                  )
                else
                  const Icon(Icons.hourglass_bottom, color: AppColors.accent),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                _badge('AI: $aiDecision', aiColor),
                _badge('Parent: $parentDecision', parentColor),
              ],
            ),
            if (imageUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProofImageViewer(
                      imageUrl: imageUrl,
                      taskDescription: taskDesc,
                      aiResult: proof,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
            if (proof['parent_note'] != null &&
                (proof['parent_note'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.comment,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        proof['parent_note'],
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (parentDecision == 'pending') ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _promptDecision(proof['id'], 'rejected'),
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.danger,
                    ),
                    label: const Text(
                      'Reject',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _promptDecision(proof['id'], 'approved'),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
