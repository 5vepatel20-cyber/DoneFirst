import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../services/blocking_service.dart';
import '../services/break_service.dart';
import '../services/notification_service.dart';
import '../services/kid_device_service.dart';
import '../services/streak_service.dart';
import '../theme/app_theme.dart';
import '../widgets/session_timer.dart';
import '../widgets/break_timer.dart';
import '../widgets/proof_thumbnail.dart';
import '../widgets/kid_device_event_toast_listener.dart';
import '../widgets/pin_guard.dart';
import '../widgets/destructive_confirm_dialog.dart';
import 'kid_device_pairing_screen.dart';
import 'session_complete_parent_screen.dart';
import 'proof_image_viewer.dart';
import '../models/models.dart';
import '../utils/subjects.dart';
import '../main.dart' as app;

class LockActiveScreen extends StatefulWidget {
  final String sessionId;
  final String childName;
  const LockActiveScreen({
    super.key,
    required this.sessionId,
    required this.childName,
  });

  /// Pure decision function for the auto-lift safety net.
  /// Extracted to the public class so tests can drive it without
  /// standing up the full widget tree. See the implementation in
  /// `_LockActiveScreenState._checkAutoLift` for the surrounding
  /// UX (notification, navigation to the celebration screen).
  ///
  /// Returns true iff the session should auto-lift right now.
  /// The auto-lift ignores pause by design — it's a safety net
  /// for parents who walked away. A parent who paused to "give
  /// the kid a few extra minutes" is already past the point
  /// where auto-lift was the right answer; they can extend
  /// instead.
  @visibleForTesting
  static bool shouldAutoLiftNow({
    required DateTime startedAt,
    required int? maxLiftMinutes,
    required DateTime now,
  }) {
    final max = maxLiftMinutes;
    if (max == null || max <= 0) return false;
    final autoLiftAt = startedAt.add(Duration(minutes: max));
    return !now.isBefore(autoLiftAt);
  }

  @override
  State<LockActiveScreen> createState() => _LockActiveScreenState();
}

class _LockActiveScreenState extends State<LockActiveScreen> {
  final _sessionService = SessionService();
  final _proofService = ProofService();
  final _blockingService = BlockingService();
  final _breakService = BreakService();
  final _notificationService = NotificationService();
  final _kidDeviceService = KidDeviceService();
  final _streakService = StreakService();
  List<ProofSubmission> _proofs = [];
  List<HomeworkTask> _tasks = [];
  List<BreakRequest> _breakRequests = [];
  HomeworkSession? _session;
  KidDevice? _kidDevice;
  bool _loading = true;
  bool _kidDeviceChecked = false;
  bool _paused = false;
  bool _activeBreakTimer = false;
  String? _activeBreakId;
  /// Guards the auto-lift path so a slow refresh tick (every 10s)
  /// can't call [_unlock] twice. Without this, a kid device that
  /// takes a couple of ticks to register the session-end would see
  /// the parent app re-issue endSession + a duplicate unlock snackbar.
  bool _autoLiftTriggered = false;
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
    // Realtime hookup. The RealtimeService is a singleton started
    // by ParentDashboard, so we just register a callback for the
    // duration of this screen and restore the prior handler on
    // dispose.
    _previousOnKidDeviceChanged = app.realtimeService.onKidDeviceChanged;
    app.realtimeService.onKidDeviceChanged = _onKidDeviceChanged;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _blockingService.removeListener(_onBlockingChanged);
    app.realtimeService.onKidDeviceChanged = _previousOnKidDeviceChanged;
    super.dispose();
  }

  void Function(Map<String, dynamic>)? _previousOnKidDeviceChanged;

  void _onKidDeviceChanged(Map<String, dynamic> newRow) {
    // Forward to the prior handler (probably the dashboard) so we
    // chain instead of clobbering.
    _previousOnKidDeviceChanged?.call(newRow);
    // If the change is for OUR child, refresh the chip so the
    // parent sees online/offline flip within ms instead of after
    // the next 10s timer tick.
    final changedChild = newRow['child_id'] as String?;
    if (_session == null || changedChild != _session!.childId) return;
    final newId = newRow['id'] as String?;
    // If a row was revoked, also drop it from local state.
    if (newId == _kidDevice?.id &&
        newRow['revoked_at'] != null &&
        newRow['revoked_at'] is String) {
      if (!mounted) return;
      setState(() => _kidDevice = null);
      return;
    }
    _refreshKidDevice(_session!.childId);
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
        icon = LucideIcons.ban;
        text =
            'App blocking is off. Grant the permission in Settings to enforce the lock.';
        break;
      case BlockingStatus.permissionGranted:
        background = AppColors.success.withValues(alpha: 0.08);
        icon = LucideIcons.shieldCheck;
        text = 'App blocking ready. Tap Start Lock to begin.';
        break;
      case BlockingStatus.blockingActive:
        background = AppColors.success.withValues(alpha: 0.12);
        icon = LucideIcons.lock;
        text = 'Apps are being blocked. Homework time.';
        break;
      case BlockingStatus.blockingFailed:
      case BlockingStatus.blockingError:
        background = AppColors.danger.withValues(alpha: 0.1);
        icon = LucideIcons.alertCircle;
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

  /// Small status row showing whether the kid's paired device is
  /// online right now. Matches the kid_devices_with_child view
  /// status field (online/recent/stale/revoked). "Online" = green,
  /// "recent" = amber (heartbeat in last 24h), "stale" = grey.
  /// "Revoked" or "Never" = red — the lock won't be enforced on
  /// the kid's device until they re-pair.
  Widget _buildKidDeviceChip(KidDevice device) {
    final (dotColor, label) = switch (device.status) {
      'online' => (AppColors.ok, 'Kid device online'),
      'recent' => (AppColors.warn, 'Kid device idle'),
      'stale' => (AppColors.muted, 'Kid device offline'),
      'revoked' => (AppColors.danger, 'Kid device revoked'),
      _ => (AppColors.danger, 'Kid device not connected'),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$label • ${device.deviceName ?? device.childDisplayName ?? 'Device'}',
                style: AppText.body(size: 13),
              ),
            ),
            Text(
              device.lastSeenLabel(DateTime.now()),
              style: AppText.bodySecondary(size: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when there's no paired kid device for this child at
  /// all. The parent's own phone will get the blocking broadcast
  /// (this screen's banner above handles that), but without a
  /// paired device the kid's phone won't actually be locked.
  /// The "Pair now" CTA pushes the pairing screen (PIN-gated) so
  /// the parent can fix it without leaving the session — useful
  /// when they didn't realise a kid device was needed until the
  /// lock was already running.
  Widget _buildNoKidDeviceBanner() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.warnFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.warnBd, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.warn,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No kid device paired — the lock won\'t be '
                'enforced on the kid\'s phone.',
                style: AppText.body(size: 13, color: AppColors.ink),
              ),
            ),
            TextButton(
              onPressed: _openPairing,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ink,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Pair now',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPairing() {
    // PIN-gated because pairing can generate codes / revoke devices.
    // The destination doesn't need to receive the active session id —
    // pairing itself is independent of the in-flight lock.
    PinGuard.push(
      context,
      destination: const KidDevicePairingScreen(),
      title: 'Confirm to pair a kid device',
    );
  }

  Future<void> _loadAll() async {
    // Session + proofs + break requests are independent — fire them
    // in parallel. The screen polls every 10s, so this latency shows
    // up as perceived "jank" when the kid or parent taps something
    // while a refresh is mid-flight. Kid-device status depends on
    // the session's child_id, so it serialises after.
    final results = await Future.wait([
      _sessionService.getSessionById(widget.sessionId),
      _proofService.getProofsForSession(widget.sessionId),
      _proofService.getTasks(widget.sessionId),
      // Session-scoped, not child-scoped: the parent on this screen
      // wants to see breaks for the current session only. Passing
      // sessionId to getPendingRequests (which filters by child_id)
      // silently returns zero rows because no break_request has
      // child_id = sessionId. getPendingBreaks filters by session_id.
      _breakService.getPendingBreaks(widget.sessionId),
    ]);
    _session = results[0] as HomeworkSession?;
    _proofs = results[1] as List<ProofSubmission>;
    _tasks = results[2] as List<HomeworkTask>;
    _breakRequests = results[3] as List<BreakRequest>;
    if (mounted) {
      setState(() {
        _paused = _session?.isPaused ?? false;
        _loading = false;
      });
    }
    if (_session != null) {
      await _refreshKidDevice(_session!.childId);
    } else {
      // No session — there can't be a paired kid device to consider
      // either. Mark the check done so the action buttons enable.
      if (mounted) setState(() => _kidDeviceChecked = true);
      _kidDevice = null;
    }
    await _checkAutoUnlock();
    // Auto-lift runs after auto-unlock so a session that's both
    // (a) all-proofs-approved and (b) past max_lift picks the
    // better-celebration message — the "finished" reason takes
    // priority over the "auto_lift" one.
    await _checkAutoLift();
  }

  Future<void> _refreshKidDevice(String childId) async {
    // The kid_device_service call is a single round-trip; we
    // intentionally serialise it after the session fetch because
    // we need child_id. Failures are silent — the chip just hides
    // so a stale RLS or schema issue can't break the lock screen.
    try {
      final devices = await _kidDeviceService.listDevicesForChild(childId);
      if (!mounted) return;
      setState(() {
        _kidDevice = devices.isEmpty ? null : devices.first;
        // Marked on every check (success or empty) so the action
        // buttons enable after the first attempt. Without this the
        // user could tap Pause / Approve / Unlock in the race
        // window before we knew whether a kid device existed,
        // leading to a flash of local flutter_screentime.
        _kidDeviceChecked = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _kidDevice = null;
        _kidDeviceChecked = true;
      });
    }
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
      try {
        await _sessionService.extendSession(widget.sessionId, minutes);
        await _loadAll();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lock extended by $minutes minutes')),
          );
        }
      } catch (e) {
        // Without this catch, a network blip on extendSession would
        // bail out and the parent would never see the success
        // snackbar — but worse, they'd see no error either, and
        // wouldn't know their kid's lock silently never extended.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn’t extend lock: $e'),
            backgroundColor: AppColors.danger,
          ),
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

  /// Safety net: end the session automatically when the
  /// `max_lift_minutes` ceiling is reached, even if the parent is
  /// away from the device. Without this, a parent who starts a
  /// lock, walks away, and forgets would leave the kid locked
  /// indefinitely (the parent phone's flutter_screentime is
  /// already gated off in the kid-device case). The display in
  /// SessionTimer shows the timestamp as "Auto-lift: HH:MM" so
  /// the parent knows when this will fire while they're still
  /// watching.
  ///
  /// We poll inside the 10s refresh tick rather than running a
  /// one-shot Timer so the trigger survives cold-app / OS kill
  /// resume: a fresh refresh that loads a session whose
  /// startedAt + maxLiftMinutes is already in the past will fire
  /// immediately. A one-shot Timer would lose its pending callback
  /// on cold start.
  Future<void> _checkAutoLift() async {
    if (_autoLiftTriggered) return;
    final s = _session;
    if (s == null) return;
    if (!LockActiveScreen.shouldAutoLiftNow(
      startedAt: s.startedAt,
      maxLiftMinutes: s.maxLiftMinutes,
      now: DateTime.now(),
    )) {
      return;
    }
    _autoLiftTriggered = true;
    await _unlock(reason: 'auto_lift');
  }

  /// Reconcile local blocking with the lock signal.
  ///
  /// When a kid device is paired (and not revoked), we deliberately
  /// do NOT call local flutter_screentime here — that would try to
  /// block apps on the parent's phone, which is useless if the kid
  /// has their own device, and would surface a permission error if
  /// the parent device has no usage-stats grant. Enforcement on
  /// the kid device is driven by Supabase realtime delivering the
  /// homework_sessions.status change, picked up by
  /// `kid_realtime_service.dart` in the kid app.
  ///
  /// Falls back to local blocking when no paired device exists, so
  /// the single-device mode (parent + kid on the same phone) still
  /// works as before.
  Future<void> _applyLockState({required bool active}) async {
    if (shouldSkipLocalBlockingOnKidDevice(_kidDevice)) {
      // Kid-side enforcement handles the lock via realtime.
      return;
    }
    if (active) {
      await _blockingService.startBlocking();
    } else {
      await _blockingService.stopBlocking();
    }
  }

  Future<void> _togglePause() async {
    try {
      if (_paused) {
        await _sessionService.resumeSession(widget.sessionId);
        await _applyLockState(active: true);
      } else {
        await _sessionService.pauseSession(widget.sessionId);
        await _applyLockState(active: false);
      }
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _paused
                ? 'Couldn’t resume lock: $e'
                : 'Couldn’t pause lock: $e',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _unlock({String reason = 'finished'}) async {
    await _applyLockState(active: false);
    await _sessionService.endSession(widget.sessionId);
    if (_session != null) {
      // The notification copy diverges per reason so the parent's
      // notification center + (in a future build) the data-export
      // report can distinguish "the kid finished in time" from
      // "the safety-net auto-lift fired" — useful for parents who
      // notice their kid consistently runs the full max_lift.
      final (title, body) = switch (reason) {
        'auto_lift' => (
          'Lock auto-lifted',
          '${widget.childName}\'s lock auto-lifted at the safety limit',
        ),
        _ => (
          'Session complete',
          '${widget.childName} finished homework',
        ),
      };
      await _notificationService.insertNotification(
        parentId: _session!.parentId,
        childId: _session!.childId,
        type: reason == 'auto_lift' ? 'session_auto_lift' : 'session_complete',
        title: title,
        body: body,
      );
    }
    if (!mounted) return;
    // Compute celebration stats in parallel: minutes studied
    // (from the in-memory session bounds), tasks approved for this
    // session, and the child's new streak. Wrapped in try/catch so
    // any one failure collapses the pill to "unknown" instead of
    // blocking the parent's return to the dashboard.
    int minutes = 0;
    int tasksApproved = 0;
    int streak = 0;
    final startedAt = _session?.startedAt;
    if (startedAt != null) {
      minutes = DateTime.now().difference(startedAt).inMinutes;
      if (minutes < 0) minutes = 0;
    }
    try {
      final proofs = await _proofService.getProofsForSession(widget.sessionId);
      tasksApproved = proofs
          .where((p) => p.parentDecision == 'approved')
          .length;
    } catch (_) {}
    if (_session != null) {
      try {
        streak = await _streakService.computeStreak(_session!.childId);
      } catch (_) {}
    }
    if (!mounted) return;
    // Replace the lock-active screen with the celebration, so the
    // "Back to dashboard" CTA pops back to the dashboard rather than
    // revealing the lock-active screen we just left behind.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SessionCompleteParentScreen(
          childName: widget.childName,
          minutesStudied: minutes,
          tasksCompleted: tasksApproved,
          streakDays: streak,
        ),
      ),
    );
  }

  Future<void> _handleDecision(
    String proofId,
    String decision, {
    String? note,
  }) async {
    try {
      await _proofService.updateParentDecision(
        proofId,
        decision,
        parentNote: note,
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'approved'
                ? 'Couldn’t approve proof: $e'
                : 'Couldn’t reject proof: $e',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _batchApproveAll({String? note}) async {
    // Collect pending IDs up front and fire a single batch update
    // via the service — one round-trip instead of one per proof.
    try {
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
    } catch (e) {
      // Same reasoning as _handleDecision: a single Supabase hiccup
      // here could mark some proofs approved and leave others
      // pending, and the parent would see neither the success nor
      // the failure without a snackbar.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t approve all proofs: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _batchApproveAllWithNote() async {
    final controller = TextEditingController();
    try {
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
        // _batchApproveAll can throw — without try/finally the
        // dialog controller would leak on every failed bulk
        // approve.
        await _batchApproveAll(note: note.isEmpty ? null : note);
      }
    } finally {
      // Dialog controller is local-scope; dispose on every exit
      // path (approve-all, cancel, throw).
      controller.dispose();
    }
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
                    widget.sessionId,
                    desc,
                    subject: selectedSubject,
                  );
                  await _loadAll();
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

  Future<void> _deleteTask(String taskId) async {
    try {
      await _proofService.deleteTask(taskId);
      await _loadAll();
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

  Future<void> _promptDecision(String proofId, String decision) async {
    if (decision == 'approved') {
      await _handleDecision(proofId, decision);
      return;
    }
    final noteController = TextEditingController();
    try {
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
      // _handleDecision can throw (RLS hiccup, network drop).
      // Without try/finally the controller would leak on every
      // failed reject.
      await _handleDecision(proofId, decision, note: note);
    } finally {
      // Dialog controller is local-scope; dispose on every exit
      // path (send, skip, throw). Each rejection leaks one
      // controller + listeners otherwise.
      noteController.dispose();
    }
  }

  Future<void> _handleBreak(String breakId, String decision) async {
    try {
      if (decision == 'approved') {
        await _breakService.approveBreak(breakId);
        await _applyLockState(active: false);
        setState(() {
          _activeBreakTimer = true;
          // Track the approved break id so the BreakTimer onComplete
          // and onCancel callbacks can persist the end-of-break to
          // Supabase. Without this, the kid-side realtime listener
          // would never see a status='completed' / 'cancelled' event
          // and would stay in KidLockState.onBreak forever (or until
          // the parent ended the whole session).
          _activeBreakId = breakId;
        });
      } else {
        await _breakService.denyBreak(breakId);
      }
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'approved'
                ? 'Couldn’t approve break: $e'
                : 'Couldn’t deny break: $e',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  /// Compact minute/hour formatter for the cancel + end-early
  /// dialogs. Used to surface "23m remaining" / "1h 5m left"
  /// instead of raw minutes. Kept private to this screen — if
  /// another surface needs the same shape, lift it into
  /// `lib/utils/duration_format.dart`.
  String _formatMinutes(int minutes) {
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final remaining = _session?.startedAt
            .add(Duration(minutes: _session!.minLockMinutes))
            .difference(DateTime.now());
        final pastEnd = remaining?.isNegative ?? false;
        final remainingLabel = remaining == null
            ? null
            : pastEnd
                ? 'past the planned end'
                : '${_formatMinutes(remaining.inMinutes)} left';
        final warningText = remainingLabel == null
            ? null
            : 'The lock has ${pastEnd ? "already ended" : remainingLabel} — '
                'wrapping up now still credits the kid with the time they spent. '
                'Use “Cancel session” instead if you want to discard it.';

        final confirmed = await DestructiveConfirmDialog.show(
          context,
          title: 'End ${widget.childName}\'s lock early?',
          description:
              'The lock will unlock all apps. ${widget.childName} will '
              'see the celebration screen with their stats for the time '
              'they put in so far.',
          confirmPhrase: widget.childName,
          confirmButtonLabel: 'End early',
          warningText: warningText,
        );
        if (confirmed) {
          await _unlock();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.childName, style: AppText.screenTitle()),
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
        body: KidDeviceEventToastListener(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _loadAll,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildBlockingStatusBanner(),
                    if (_kidDevice != null) _buildKidDeviceChip(_kidDevice!),
                    if (_kidDevice == null) _buildNoKidDeviceBanner(),
                    if (_session != null)
                      SessionTimer(
                        sessionStart: _session!.startedAt,
                        durationMinutes: _session!.minLockMinutes,
                        minUnlockMinutes: _session!.minLockMinutes,
                        autoLiftMinutes: _session!.maxLiftMinutes,
                        paused: _paused,
                      ),
                    const SizedBox(height: 8),
                    if (_kidDeviceChecked)
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
                          // Capture the id BEFORE clearing it; we need
                          // it for the end-of-break write below.
                          final id = _activeBreakId;
                          // Capture the messenger now so the catch
                          // block below can show a snackbar without
                          // tripping use_build_context_synchronously
                          // (we'd otherwise be using `context` after
                          // three awaits inside the try).
                          final messenger =
                              ScaffoldMessenger.of(context);
                          setState(() {
                            _activeBreakTimer = false;
                            _activeBreakId = null;
                          });
                          try {
                            // Persist the end-of-break so the kid app's
                            // realtime listener flips out of onBreak
                            // and re-engages the lock.
                            if (id != null) {
                              await _breakService.endBreak(id);
                            }
                            await _applyLockState(active: true);
                            await _loadAll();
                          } catch (e) {
                            // Without this catch, a network blip on
                            // endBreak would leave the BreakTimer UI
                            // cleared but the kid-side lock still
                            // paused — the parent would think the
                            // break ended cleanly. Surface it so
                            // they know to retry from the dashboard.
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Break ended but didn’t sync: $e. '
                                  'Tap Refresh on the dashboard.',
                                ),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                          }
                        },
                        onCancel: () async {
                          final id = _activeBreakId;
                          final messenger =
                              ScaffoldMessenger.of(context);
                          setState(() {
                            _activeBreakTimer = false;
                            _activeBreakId = null;
                          });
                          try {
                            // Distinguish parent-cancelled from timer-
                            // completed in the data-export report.
                            if (id != null) {
                              await _breakService.cancelBreak(id);
                            }
                            await _applyLockState(active: true);
                            await _loadAll();
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Break cancelled but didn’t sync: $e. '
                                  'Tap Refresh on the dashboard.',
                                ),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                    // ── Homework Tasks ──────────────────────────────
                    if (_tasks.isNotEmpty || true) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    LucideIcons.listChecks,
                                    size: 16,
                                    color: AppColors.forest,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Homework tasks',
                                    style: AppText.cardHeader(
                                      color: AppColors.forest,
                                      size: 14,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_tasks.where((t) => !t.isPending).length}/${_tasks.length}',
                                    style: AppText.bodySecondary(size: 12),
                                  ),
                                ],
                              ),
                              if (_tasks.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ...(_tasks.map(
                                  (t) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        Icon(
                                          t.isPending
                                              ? LucideIcons.circle
                                              : LucideIcons.checkCircle2,
                                          size: 16,
                                          color: t.isPending
                                              ? AppColors.muted
                                              : AppColors.success,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            t.description,
                                            style: AppText.body(size: 13),
                                          ),
                                        ),
                                        if (t.isPending)
                                          GestureDetector(
                                            onTap: () => _deleteTask(t.id),
                                            child: const Icon(
                                              LucideIcons.trash2,
                                              size: 14,
                                              color: AppColors.muted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                )),
                              ] else
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'No tasks yet. Add tasks for your kid.',
                                    style: AppText.bodySecondary(size: 12),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _showAddTaskDialog,
                                  icon: const Icon(LucideIcons.plus, size: 16),
                                  label: const Text('Add task'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.forest,
                                    side: const BorderSide(
                                      color: AppColors.hair2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
                          // Goes through the with-note dialog so the
                          // parent can attach an optional
                          // encouragement ("Great work!", "Nice
                          // handwriting") to every approved proof.
                          // Skip-the-note is one tap — just hit
                          // "Approve All" in the dialog.
                          onPressed: _batchApproveAllWithNote,
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
                      LucideIcons.messageSquare,
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
                      LucideIcons.x,
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
                    icon: const Icon(LucideIcons.check, size: 18),
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
