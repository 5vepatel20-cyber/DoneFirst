import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../services/blocking_service.dart';
import '../services/break_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/session_timer.dart';
import '../widgets/break_timer.dart';
import '../widgets/proof_thumbnail.dart';
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
    // Session + proofs + break requests are independent — fire them
    // in parallel. The screen polls every 10s, so this latency shows
    // up as perceived "jank" when the kid or parent taps something
    // while a refresh is mid-flight.
    final results = await Future.wait([
      _sessionService.getSessionById(widget.sessionId),
      _proofService.getProofsForSession(widget.sessionId),
      _breakService.getPendingRequests(widget.sessionId),
    ]);
    _session = results[0] as HomeworkSession?;
    _proofs = results[1] as List<ProofSubmission>;
    _breakRequests = results[2] as List<BreakRequest>;
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
    // Collect pending IDs up front and fire a single batch update
    // via the service — one round-trip instead of one per proof.
    final pendingIds = _proofs
        .where((p) => p.isPending)
        .map((p) => p.id)
        .toList(growable: false);
    if (pendingIds.isNotEmpty) {
      await _proofService.batchApproveOrReject(
        pendingIds,
        'approved',
        parentNote: note,
      );
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
    // Common-reason chips. Tapping one overwrites the note text so
    // the parent can still tweak it before sending. Most rejections
    // fall into one of these buckets; typing the same sentence 5
    // times a night adds up. "Custom…" appends a back to keep the
    // field editable — without it, a custom reject would require
    // clearing the chip first.
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reason for rejection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final r in const [
                  'Too blurry',
                  'Wrong subject',
                  'Incomplete work',
                  'Didn\'t show the work',
                  'Needs to be darker',
                  'Try again',
                ])
                  ActionChip(
                    label: Text(r, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      noteController.text = r;
                      noteController.selection = TextSelection.fromPosition(
                        TextPosition(offset: noteController.text.length),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Tell your child what to fix...',
                labelText: 'Note (optional)',
              ),
            ),
          ],
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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${widget.childName}', style: AppText.screenTitle()),
              const SizedBox(height: 2),
              Text('Lock active', style: AppText.eyebrow()),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: _unlock,
              icon: const Icon(LucideIcons.unlock, size: 16),
              label: const Text('Unlock'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
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
                              _paused
                                  ? LucideIcons.play
                                  : LucideIcons.pause,
                            ),
                            label: Text(_paused ? 'Resume' : 'Pause'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _extendSession,
                            icon: const Icon(LucideIcons.timer, size: 16),
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
                        color: AppColors.warnFill,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          side: const BorderSide(color: AppColors.warnBd),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    LucideIcons.coffee,
                                    size: 16,
                                    color: AppColors.warn,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Break request',
                                    style: AppText.cardHeader(
                                      color: AppColors.warn,
                                      size: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...(_breakRequests.map(
                                (br) => Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Child wants a 5 minute break',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          _handleBreak(br.id, 'approved'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.ok,
                                      ),
                                      child: const Text('Allow'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          _handleBreak(br.id, 'rejected'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.danger,
                                      ),
                                      child: const Text('Deny'),
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
                          icon: const Icon(LucideIcons.checkCheck, size: 18),
                          label: const Text('Approve all'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_proofs.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              const Icon(
                                LucideIcons.hourglass,
                                size: 48,
                                color: AppColors.muted,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Waiting for proof submissions…',
                                style: AppText.listTitle(),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Auto-refreshes every 10s',
                                style: AppText.bodySecondary(size: 12),
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
                    proof.isApproved
                        ? LucideIcons.checkCircle2
                        : LucideIcons.xCircle,
                    color: parentColor,
                  )
                else
                  const Icon(
                    LucideIcons.hourglass,
                    size: 18,
                    color: AppColors.muted,
                  ),
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
                child: ProofThumbnail(
                  url: proof.imageUrl,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
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
