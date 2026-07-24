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
import '../widgets/df_kit.dart';
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
    final DfPillTone tone;
    final IconData icon;
    final String text;
    switch (status) {
      case BlockingStatus.permissionDenied:
        tone = DfPillTone.danger;
        icon = LucideIcons.ban;
        text =
            'App pausing is off. Grant the permission in Settings to enforce the lock.';
        break;
      case BlockingStatus.permissionGranted:
        tone = DfPillTone.success;
        icon = LucideIcons.shieldCheck;
        text = 'App pausing ready.';
        break;
      case BlockingStatus.blockingActive:
        tone = DfPillTone.success;
        icon = LucideIcons.lock;
        text = 'Apps are paused. Homework time.';
        break;
      case BlockingStatus.blockingFailed:
      case BlockingStatus.blockingError:
        tone = DfPillTone.danger;
        icon = LucideIcons.alertCircle;
        text =
            'Pausing failed: ${_blockingService.lastError ?? 'unknown error'}';
        break;
      default:
        return const SizedBox.shrink();
    }
    final c = switch (tone) {
      DfPillTone.danger => (AppColors.dangerFg, AppColors.dangerBg),
      _ => (AppColors.green, AppColors.greenTint),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DfCard(
        color: c.$2,
        borderColor: c.$1.withValues(alpha: 0.3),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: c.$1),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppText.bodySecondary(size: 13))),
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
    final (tone, label) = switch (device.status) {
      'online' => (DfPillTone.success, 'Online'),
      'recent' => (DfPillTone.attention, 'Idle'),
      'stale' => (DfPillTone.neutral, 'Offline'),
      'revoked' => (DfPillTone.danger, 'Revoked'),
      _ => (DfPillTone.danger, 'Not connected'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DfCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(
              LucideIcons.smartphone,
              size: 18,
              color: AppColors.ink45,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                device.deviceName ?? device.childDisplayName ?? 'Kid device',
                style: AppText.listTitle(size: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DfStatusPill(label, tone: tone, dot: true),
            const SizedBox(width: 8),
            Text(
              device.lastSeenLabel(DateTime.now()),
              style: AppText.caption(),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DfCard(
        color: AppColors.amberTint,
        borderColor: AppColors.amberTint2,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(
              LucideIcons.triangleAlert,
              size: 18,
              color: AppColors.amberDeep,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No kid device paired — the lock won\'t be '
                'enforced on the kid\'s phone.',
                style: AppText.bodySecondary(size: 13),
              ),
            ),
            const SizedBox(width: 8),
            DfButton.outline(
              'Pair now',
              expand: false,
              onPressed: _openPairing,
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
            _paused ? 'Couldn’t resume lock: $e' : 'Couldn’t pause lock: $e',
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
        _ => ('Session complete', '${widget.childName} finished homework'),
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
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
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
                      if (_session != null) ...[
                        Row(
                          children: [
                            DfStatusPill(
                              _paused ? 'Paused' : 'Live',
                              tone: _paused
                                  ? DfPillTone.attention
                                  : DfPillTone.success,
                              dot: true,
                            ),
                            const Spacer(),
                            Text(
                              '${_tasks.where((t) => !t.isPending).length} of '
                              '${_tasks.length} tasks done',
                              style: AppText.bodySecondary(size: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SessionTimer(
                          sessionStart: _session!.startedAt,
                          durationMinutes: _session!.minLockMinutes,
                          minUnlockMinutes: _session!.minLockMinutes,
                          autoLiftMinutes: _session!.maxLiftMinutes,
                          paused: _paused,
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (_kidDeviceChecked)
                        Row(
                          children: [
                            Expanded(
                              child: DfButton.outline(
                                _paused ? 'Resume' : 'Pause',
                                icon: _paused
                                    ? LucideIcons.play
                                    : LucideIcons.pause,
                                onPressed: _togglePause,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DfButton.outline(
                                '+15 min',
                                icon: LucideIcons.timer,
                                onPressed: _extendSession,
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
                            final messenger = ScaffoldMessenger.of(context);
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
                            final messenger = ScaffoldMessenger.of(context);
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
                      ...[
                        const SizedBox(height: 12),
                        DfCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const DfSectionLabel('Tasks'),
                              if (_tasks.isNotEmpty)
                                ..._tasks.map(
                                  (t) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            t.description,
                                            style: AppText.listTitle(size: 14),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _taskPill(t),
                                        if (t.isPending) ...[
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _deleteTask(t.id),
                                            child: const Icon(
                                              LucideIcons.trash2,
                                              size: 15,
                                              color: AppColors.ink45,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    'No tasks yet. Add tasks for your kid.',
                                    style: AppText.bodySecondary(size: 13),
                                  ),
                                ),
                              const SizedBox(height: 4),
                              DfButton.outline(
                                'Add task',
                                icon: LucideIcons.plus,
                                onPressed: _showAddTaskDialog,
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_breakRequests.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DfCard(
                          color: AppColors.amberTint,
                          borderColor: AppColors.amberTint2,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    LucideIcons.coffee,
                                    size: 16,
                                    color: AppColors.amberDeep,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Break request',
                                    style: AppText.cardHeader(
                                      color: AppColors.amberDeep,
                                      size: 15,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ..._breakRequests.map(
                                (br) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Wants a 5 minute break',
                                          style: AppText.body(size: 14),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      DfButton(
                                        'Allow',
                                        expand: false,
                                        onPressed: () =>
                                            _handleBreak(br.id, 'approved'),
                                      ),
                                      const SizedBox(width: 8),
                                      DfButton.outline(
                                        'Deny',
                                        expand: false,
                                        onPressed: () =>
                                            _handleBreak(br.id, 'rejected'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_proofs.any((p) => p.isPending)) ...[
                        const SizedBox(height: 12),
                        DfButton(
                          // Goes through the with-note dialog so the
                          // parent can attach an optional
                          // encouragement ("Great work!", "Nice
                          // handwriting") to every approved proof.
                          // Skip-the-note is one tap — just hit
                          // "Approve All" in the dialog.
                          'Approve all (${_proofs.where((p) => p.isPending).length})',
                          icon: LucideIcons.checkCheck,
                          onPressed: _batchApproveAllWithNote,
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (_proofs.isEmpty)
                        DfCard(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.greenTint,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.tile,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  LucideIcons.hourglass,
                                  size: 26,
                                  color: AppColors.green,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Waiting for proof…',
                                style: AppText.cardHeader(size: 17),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Auto-refreshes every 10s',
                                style: AppText.bodySecondary(size: 13),
                              ),
                            ],
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

  /// Status pill for a task row: To do / Checking… / Approved / Rejected.
  Widget _taskPill(HomeworkTask t) {
    final (label, tone) = switch (t.status) {
      'approved' => ('Approved', DfPillTone.success),
      'submitted' => ('Checking…', DfPillTone.info),
      'rejected' => ('Try again', DfPillTone.danger),
      _ => ('To do', DfPillTone.neutral),
    };
    return DfStatusPill(label, tone: tone);
  }

  Widget _buildProofCard(ProofSubmission proof) {
    final taskDesc = proof.taskDescription ?? 'Task';
    final aiDecision = proof.aiDecision ?? 'pending';
    final confidence = proof.aiConfidence;

    // AI verdict line, mock: "Looks like real homework · AI confidence · 96%".
    final (verdict, _) = switch (aiDecision) {
      'approved' => ('Looks like real homework', DfPillTone.success),
      'rejected' => ('Needs another look', DfPillTone.danger),
      'needs_review' => ('Worth a closer look', DfPillTone.attention),
      _ => ('Checking the photo…', DfPillTone.info),
    };
    final parentTone = proof.isApproved
        ? DfPillTone.success
        : proof.isRejected
        ? DfPillTone.danger
        : DfPillTone.neutral;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DfCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (proof.isPending)
                  DfStatusPill('Just submitted', tone: DfPillTone.info)
                else
                  DfStatusPill(
                    proof.isApproved ? 'Approved' : 'Rejected',
                    tone: parentTone,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (proof.imageUrl.isNotEmpty) ...[
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
                  borderRadius: BorderRadius.circular(AppRadius.tile),
                  child: ProofThumbnail(
                    url: proof.imageUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(taskDesc, style: AppText.cardHeader(size: 17)),
            const SizedBox(height: 8),
            // AI verdict + confidence panel (info tone).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(AppRadius.tile),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.sparkles,
                    size: 16,
                    color: AppColors.infoFg,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      confidence != null
                          ? '$verdict · AI confidence · '
                                '${(confidence * 100).round()}%'
                          : verdict,
                      style: AppText.bodySecondary(
                        size: 13,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (proof.aiReason != null && proof.aiReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(proof.aiReason!, style: AppText.bodySecondary(size: 12.5)),
            ],
            if (proof.parentNote != null && proof.parentNote!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.greenTint,
                  borderRadius: BorderRadius.circular(AppRadius.tile),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      LucideIcons.messageSquare,
                      size: 14,
                      color: AppColors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        proof.parentNote!,
                        style: AppText.bodySecondary(size: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (proof.isPending) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DfButton(
                      'Approve',
                      icon: LucideIcons.check,
                      onPressed: () => _promptDecision(proof.id, 'approved'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DfButton.outline(
                      'Ask again',
                      onPressed: () => _promptDecision(proof.id, 'rejected'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
