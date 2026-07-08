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
import '../widgets/break_timer.dart';
import 'proof_image_viewer.dart';
import '../models/models.dart';

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
  List<ProofSubmission> _proofs = [];
  List<BreakRequest> _breakRequests = [];
  HomeworkSession? _session;
  bool _loading = true;
  bool _paused = false;
  bool _activeBreakTimer = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _blockingService.addListener(_onBlockingChanged);
    _loadAll();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadAll(),
    );
    // Kid-side permission request. On first run, this prompts for the
    // OS-level grant (FamilyControls on iOS, UsageStats on Android).
    // On web this is a no-op. If the user denies, the banner below
    // explains how to fix it.
    if (!_blockingService.hasPermission) {
      _blockingService.requestPermission();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _blockingService.removeListener(_onBlockingChanged);
    super.dispose();
  }

  void _onBlockingChanged() {
    if (!mounted) return;
    if (_blockingService.isError && _blockingService.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Blocking error: ${_blockingService.lastError}'),
          backgroundColor: AppColors.danger,
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: _blockingService.acknowledgeError,
          ),
        ),
      );
    }
    setState(() {});
  }

  Widget _buildBlockingStatusBanner() {
    final status = _blockingService.status;
    final Color background;
    final IconData icon;
    final String text;
    switch (status) {
      case BlockingStatus.permissionDenied:
        background = AppColors.danger.withValues(alpha: 0.1);
        icon = Icons.block;
        text =
            'App blocking is off. Grant the permission in Settings to enforce the lock.';
        break;
      case BlockingStatus.permissionGranted:
        background = AppColors.success.withValues(alpha: 0.08);
        icon = Icons.shield_outlined;
        text = 'App blocking ready. Tap Start Lock to begin.';
        break;
      case BlockingStatus.blockingActive:
        background = AppColors.success.withValues(alpha: 0.12);
        icon = Icons.lock;
        text = 'Apps are being blocked. Homework time.';
        break;
      case BlockingStatus.blockingFailed:
      case BlockingStatus.blockingError:
        background = AppColors.danger.withValues(alpha: 0.1);
        icon = Icons.error_outline;
        text =
            'Blocking failed: ${_blockingService.lastError ?? 'unknown error'}';
        break;
      default:
        return const SizedBox.shrink();
    }
    return Card(
      color: background,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  Future<void> _loadAll() async {
    _session = await _sessionService.getSessionById(widget.sessionId);
    _proofs = await _proofService.getProofsForSession(widget.sessionId);
    _breakRequests = await _breakService.getPendingRequests(widget.sessionId);
    if (mounted)
      setState(() {
        _paused = _session?.isPaused ?? false;
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
    final allDecided = _proofs.every((p) => p.parentDecision != 'pending');
    if (allDecided) {
      final allApproved = _proofs.every((p) => p.isApproved);
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
      await _notificationService.insertNotification(
        parentId: _session!.parentId,
        childId: _session!.childId,
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

  Future<void> _batchApproveAll({String? note}) async {
    for (final p in _proofs) {
      if (p.isPending) {
        await _proofService.updateParentDecision(
          p.id,
          'approved',
          parentNote: note,
        );
      }
    }
    if (_session != null) {
      await _notificationService.insertNotification(
        parentId: _session!.parentId,
        childId: _session!.childId,
        type: 'proof_submitted',
        title: 'All proofs approved',
        body: '${widget.childName}\'s homework all approved',
      );
    }
    await _loadAll();
  }

  Future<void> _batchApproveAllWithNote() async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Note (optional)'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Great work! ...',
            labelText: 'Note for your child',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Approve All'),
          ),
        ],
      ),
    );
    if (note != null) {
      await _batchApproveAll(note: note.isEmpty ? null : note);
    }
  }

  Future<void> _cancelSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Session?'),
        content: const Text(
          'This will cancel the current homework session. '
          'All apps will be unlocked and progress will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Cancel Session'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _blockingService.stopBlocking();
      await _sessionService.cancelSession(widget.sessionId);
      if (mounted) Navigator.pop(context);
    }
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
    if (decision == 'approved') {
      await _breakService.approveBreak(breakId);
      await _blockingService.stopBlocking();
      setState(() => _activeBreakTimer = true);
    } else {
      await _breakService.denyBreak(breakId);
    }
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('End Lock?'),
            content: const Text(
              'The homework lock is still active. Ending early will unlock all apps.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay Locked'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                child: const Text('Unlock Early'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await _unlock();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.childName} — Lock Active'),
          actions: [
            TextButton(onPressed: _unlock, child: const Text('Unlock Early')),
            TextButton(
              onPressed: _cancelSession,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Cancel'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadAll,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildBlockingStatusBanner(),
                    if (_session != null)
                      SessionTimer(
                        sessionStart: _session!.startedAt,
                        durationMinutes: _session!.minLockMinutes,
                        minUnlockMinutes: _session!.minLockMinutes,
                        autoLiftMinutes: _session!.maxLiftMinutes,
                        paused: _paused,
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _togglePause,
                            icon: Icon(
                              _paused ? Icons.play_arrow : Icons.pause,
                            ),
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
                    if (_activeBreakTimer) ...[
                      const SizedBox(height: 12),
                      BreakTimer(
                        onComplete: () async {
                          setState(() => _activeBreakTimer = false);
                          await _blockingService.startBlocking();
                          await _loadAll();
                        },
                        onCancel: () async {
                          setState(() => _activeBreakTimer = false);
                          await _blockingService.startBlocking();
                          await _loadAll();
                        },
                      ),
                    ],
                    if (_breakRequests.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: AppColors.info.withValues(alpha: 0.08),
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
                              ...(_breakRequests.map(
                                (br) => Row(
                                  children: [
                                    const Expanded(
                                      child: Text('Child wants a break'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          _handleBreak(br.id, 'approved'),
                                      child: const Text(
                                        'Allow',
                                        style: TextStyle(
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          _handleBreak(br.id, 'rejected'),
                                      child: const Text(
                                        'Deny',
                                        style: TextStyle(
                                          color: AppColors.danger,
                                        ),
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
                    if (_proofs.any((p) => p.isPending)) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _batchApproveAll(),
                          icon: const Icon(Icons.done_all),
                          label: const Text('Approve All'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _batchApproveAllWithNote(),
                          icon: const Icon(Icons.note_add, size: 18),
                          label: const Text('Approve All with Note'),
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
                      ...(_proofs.map((proof) => _buildProofCard(proof))),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildProofCard(ProofSubmission proof) {
    final taskDesc = proof.taskDescription ?? 'Task';
    final aiDecision = proof.aiDecision ?? 'pending';
    final parentDecision = proof.parentDecision;

    final aiColor = aiDecision == 'approved'
        ? AppColors.success
        : aiDecision == 'rejected'
        ? AppColors.danger
        : AppColors.accent;
    final parentColor = proof.isApproved
        ? AppColors.success
        : proof.isRejected
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
                if (!proof.isPending)
                  Icon(
                    proof.isApproved ? Icons.check_circle : Icons.cancel,
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
            if (proof.imageUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProofImageViewer(
                      imageUrl: proof.imageUrl,
                      taskDescription: taskDesc,
                      aiResult: proof,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    proof.imageUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
            if (proof.parentNote != null && proof.parentNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
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
                        proof.parentNote!,
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
            if (proof.isPending) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _promptDecision(proof.id, 'rejected'),
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
                    onPressed: () => _promptDecision(proof.id, 'approved'),
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
