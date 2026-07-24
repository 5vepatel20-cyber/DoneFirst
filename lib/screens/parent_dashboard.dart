import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../services/notification_service.dart';
import '../services/schedule_service.dart';
import '../services/proof_service.dart';
import '../services/kid_device_service.dart';
import '../services/break_service.dart';
import '../main.dart' as app;
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/monogram_avatar.dart';
import '../widgets/consent_gate.dart';
import '../widgets/pin_guard.dart';
import '../widgets/destructive_confirm_dialog.dart';
import 'auth_screen.dart';
import 'lock_config_screen.dart';
import 'lock_active_screen.dart';
import 'proof_review_screen.dart';
import 'kid_home_screen.dart';
import 'settings_screen.dart';
import 'upgrade_screen.dart';
import 'sessions_stats_screen.dart';
import 'schedules_screen.dart';
import 'proof_gallery_screen.dart';
import 'kid_profile_screen.dart';
import 'notification_center_screen.dart';
import 'pending_proofs_screen.dart';
import 'kid_device_pairing_screen.dart';
import 'child_homework_screen.dart';
import '../widgets/kid_device_event_toast_listener.dart';
import '../widgets/kid_device_setup_hint_card.dart';
import '../widgets/kid_device_status_caption.dart';
import '../widgets/recent_kid_device_activity_card.dart';

class ParentDashboard extends StatefulWidget {
  const ParentDashboard({super.key});

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  // Cap for the child-name input on rename. 30 keeps most cultures'
  // full names fitting (Western three-token names plus a few
  // characters of breathing room) while preventing "look at me"
  // walls of text in the dashboard's _ChildRow avatar.
  static const _maxChildNameLength = 30;

  final _auth = AuthService();
  final _sessionService = SessionService();
  final _notificationService = NotificationService();
  final _scheduleService = ScheduleService();
  final _proofService = ProofService();
  final _kidDeviceService = KidDeviceService();
  final _breakService = BreakService();
  List<Child> _children = [];
  final Map<String, bool> _activeLocks = {};
  final Map<String, int> _pendingProofs = {};
  final Map<String, int> _pendingBreaks = {};

  /// kid-device status per child for the dashboard's per-row dot +
  /// last-seen label. null = no paired device for that child,
  /// otherwise the derived status string ('online' / 'recent' /
  /// 'stale' / 'revoked') plus the raw last_seen_at timestamp.
  final Map<String, ({String status, DateTime? lastSeenAt})?> _kidDeviceStatus =
      {};
  bool _loading = true;
  int _monthlySessionCount = 0;
  int _unreadNotifications = 0;
  int _totalSessions = 0;
  int _totalMinutes = 0;
  int _totalApproved = 0;
  int _mistralCallsToday = 0;
  // Saved realtime callback handles. The dashboard overwrites these
  // on the singleton RealtimeService in initState; on dispose we
  // restore them so a screen that was on top (e.g. lock_active_screen,
  // which also binds onKidDeviceChanged) doesn't end up with null
  // callbacks after the user navigates back here.
  VoidCallback? _previousOnNewNotification;
  VoidCallback? _previousOnNewProof;
  VoidCallback? _previousOnNewBreakRequest;
  void Function(Map<String, dynamic>)? _previousOnKidDeviceChanged;
  List<RecurringSchedule> _todaySchedules = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
    app.realtimeService.startListening();
    // Save the previous handlers so dispose() can restore them.
    // Without this, navigating back to the dashboard after a child
    // screen (lock_active_screen, kid_device_pairing_screen, etc.)
    // that already set onKidDeviceChanged would leave it null —
    // those screens rely on save/restore in their own initState/
    // dispose, but if the dashboard overwrote it on the way out,
    // they save the dashboard's closure, which then leaks after
    // the dashboard disposes.
    _previousOnNewNotification = app.realtimeService.onNewNotification;
    _previousOnNewProof = app.realtimeService.onNewProof;
    _previousOnNewBreakRequest = app.realtimeService.onNewBreakRequest;
    _previousOnKidDeviceChanged = app.realtimeService.onKidDeviceChanged;
    app.realtimeService.onNewNotification = () {
      _notificationService.getUnreadCount().then((count) {
        if (mounted) setState(() => _unreadNotifications = count);
      });
    };
    app.realtimeService.onNewProof = () {
      setState(() {});
    };
    app.realtimeService.onNewBreakRequest = () {
      _loadAll();
    };
    // kid_devices UPDATE fires on every heartbeat (last_seen_at
    // bump) and on every revoke (revoked_at set). The fastest
    // correct path is to refetch that single child — a refetch
    // of the whole dashboard is overkill and causes a visible
    // "flash" because we'd reset _loading = true.
    app.realtimeService.onKidDeviceChanged = _onKidDeviceChanged;
  }

  @override
  void dispose() {
    // Tear down realtime so the WebSocket channels don't stay
    // subscribed after the user signs out or navigates away.
    // Without this, onNewKidDeviceEvent etc. continue firing on a
    // disposed State (closures captured the State) — they'd hit
    // `if (mounted) ...` guards but still hold memory and burn
    // battery. stopListening is idempotent so calling it on the
    // happy-path navigation away is also safe.
    app.realtimeService.stopListening();
    app.realtimeService.onNewNotification = _previousOnNewNotification;
    app.realtimeService.onNewProof = _previousOnNewProof;
    app.realtimeService.onNewBreakRequest = _previousOnNewBreakRequest;
    app.realtimeService.onKidDeviceChanged = _previousOnKidDeviceChanged;
    super.dispose();
  }

  void _onKidDeviceChanged(Map<String, dynamic> newRow) {
    final childId = newRow['child_id'] as String?;
    if (childId == null) return;
    _kidDeviceService
        .listDevicesForChild(childId)
        .then((devices) {
          if (!mounted) return;
          // Prefer a non-revoked device so the dashboard doesn't show
          // "revoked" for a child who has since re-paired.
          final best = devices.isEmpty
              ? null
              : devices.firstWhere(
                  (d) => !d.isRevoked,
                  orElse: () => devices.first,
                );
          setState(() {
            _kidDeviceStatus[childId] = best == null
                ? null
                : (status: best.status, lastSeenAt: best.lastSeenAt);
          });
        })
        .catchError((_) {});
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    // Capture messenger BEFORE the awaits so the catch block below
    // can show a snackbar without tripping
    // use_build_context_synchronously (we'd otherwise be reading
    // `context` after a real network round-trip).
    final messenger = ScaffoldMessenger.of(context);
    final parentId = _auth.currentUser?.id;
    if (parentId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      await _sessionService.getOrCreateFamily();
      final children = await _sessionService.getChildren(parentId);
      setState(() => _children = children);

      // Fan-out: monthly count, mistral usage, unread notifications,
      // today's schedules, and the parent's family_id are all
      // independent reads. Fire them in parallel so the dashboard
      // loads in max(latencies) instead of sum(latencies).
      final results = await Future.wait([
        _sessionService.getMonthlySessionCount(parentId),
        _proofService.getMistralCallsToday(),
        _notificationService.getUnreadCount(),
        _scheduleService.getTodaySchedules(),
        Supabase.instance.client
            .from('parents')
            .select('family_id')
            .eq('id', parentId)
            .single(),
      ]);
      _monthlySessionCount = results[0] as int;
      _mistralCallsToday = results[1] as int;
      _unreadNotifications = results[2] as int;
      _todaySchedules = (results[3] as List).cast<RecurringSchedule>();
      final family = results[4] as Map<String, dynamic>;

      if (family['family_id'] != null) {
        final allChildren = await Supabase.instance.client
            .from('children')
            .select('id')
            .eq('family_id', family['family_id']);
        final childIds = allChildren.map((c) => c['id'] as String).toList();
        if (childIds.isNotEmpty) {
          // Two more independent reads — sessions for total stats,
          // approved proofs for the totals row. Run in parallel.
          final totalsResults = await Future.wait([
            Supabase.instance.client
                .from('homework_sessions')
                .select('id, duration_minutes')
                .inFilter('child_id', childIds),
            Supabase.instance.client
                .from('proof_submissions')
                .select('id')
                .eq('parent_decision', 'approved'),
          ]);
          final allSessions = totalsResults[0] as List;
          final approvedProofs = totalsResults[1] as List;
          _totalSessions = allSessions.length;
          _totalMinutes = allSessions.fold<int>(
            0,
            (sum, s) => sum + ((s['duration_minutes'] as int?) ?? 0),
          );
          _totalApproved = approvedProofs.length;
        }
      }

      // Per-child loads run in parallel both across children AND
      // within each child. The four reads per child (active
      // session, pending proofs, pending breaks, kid-device
      // status) are independent of each other, so fan them out
      // alongside the per-child fan-out. For a 3-kid family this
      // collapses 12 sequential round-trips into a single
      // max(latency) window.
      final perChild = await Future.wait(
        _children.map((child) async {
          // The 4 per-child reads are independent of each other,
          // so fire them all at once. Each one is wrapped in a
          // fail-soft catch so a transient RLS hiccup on one row
          // doesn't kill the rest of the dashboard.
          HomeworkSession? session;
          int pending = _pendingProofs[child.id] ?? 0;
          // Pending-proof count per child for the inbox chip. If
          // this throws (e.g. RLS still pending), leave the prior
          // value alone rather than wipe it to 0.
          int pendingBreaks = _pendingBreaks[child.id] ?? 0;
          ({String status, DateTime? lastSeenAt})? deviceStatus;

          await Future.wait([
            Future(() async {
              try {
                session = await _sessionService.getActiveSession(child.id);
              } catch (_) {}
            }),
            Future(() async {
              try {
                final proofs = await _proofService.getPendingProofs(child.id);
                pending = proofs.length;
              } catch (_) {}
            }),
            Future(() async {
              try {
                final breaks = await _breakService.getPendingRequests(child.id);
                pendingBreaks = breaks.length;
              } catch (_) {}
            }),
            Future(() async {
              try {
                final devices = await _kidDeviceService.listDevicesForChild(
                  child.id,
                );
                if (devices.isNotEmpty) {
                  // Prefer a non-revoked device.
                  final best = devices.firstWhere(
                    (d) => !d.isRevoked,
                    orElse: () => devices.first,
                  );
                  deviceStatus = (
                    status: best.status,
                    lastSeenAt: best.lastSeenAt,
                  );
                }
              } catch (_) {}
            }),
          ]);
          return MapEntry(child.id, (
            session != null,
            pending,
            pendingBreaks,
            deviceStatus,
          ));
        }),
      );
      for (final entry in perChild) {
        _activeLocks[entry.key] = entry.value.$1;
        _pendingProofs[entry.key] = entry.value.$2;
        _pendingBreaks[entry.key] = entry.value.$3;
        _kidDeviceStatus[entry.key] = entry.value.$4;
      }
    } catch (e) {
      // Top-level catch covers getOrCreateFamily / getChildren /
      // monthly counts / family_id / totals reads. Without this
      // the dashboard silently shows an empty list and the
      // parent has no idea why. The per-child reads inside are
      // fail-soft (each wrapped in its own catch) so a hiccup on
      // one child doesn't blow away the whole load — which means
      // the per-child catches were always doing the right thing,
      // but they were silently swallowing network errors on the
      // top-level reads too.
      messenger.showSnackBar(
        SnackBar(
          content: Text('Couldn’t load dashboard: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// True if the family has at least one child on the dashboard
  /// but no paired kid device for any of them. Drives the empty-
  /// state hint that nudges parents toward the kid-app setup.
  bool get _hasUnpairedChildren {
    if (_children.isEmpty) return false;
    for (final child in _children) {
      final status = _kidDeviceStatus[child.id];
      // A paired device shows up with a non-null derived status
      // ('online' / 'recent' / 'stale' / 'revoked'). null means
      // we couldn't find one in kid_devices_with_child.
      if (status != null) return false;
    }
    return true;
  }

  Future<void> _addChild() async {
    final controller = TextEditingController();
    // The palette + emoji set intentionally duplicates the constants
    // in kid_profile_screen.dart. Inline copy rather than a shared
    // file because the two screens want slightly different layouts
    // (a Wrap of swatches vs a dialog-internal row) and centralising
    // would force a 3rd file for one color list.
    final List<Color> kidColors = [
      AppColors.primary,
      AppColors.accent,
      AppColors.success,
      AppColors.info,
      AppColors.danger,
      AppColors.warning,
      const Color(0xFFE91E63),
      const Color(0xFF00BCD4),
    ];
    const List<String> kidEmojis = [
      '🧑',
      '👧',
      '👦',
      '🧒',
      '👩',
      '👨',
      '🧑‍🎓',
      '🌟',
    ];
    int selectedColor = 0;
    int selectedEmoji = 0;
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add Child'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Live preview — updates as the parent picks. Kids
                  // love picking their own avatar; the preview turns
                  // abstract swatches into "this is what you'll see".
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: kidColors[selectedColor].withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          kidEmojis[selectedEmoji],
                          style: const TextStyle(fontSize: 36),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: "Child's Name",
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Color',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(
                      kidColors.length,
                      (i) => GestureDetector(
                        onTap: () => setLocal(() => selectedColor = i),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: kidColors[i],
                            shape: BoxShape.circle,
                            border: selectedColor == i
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: selectedColor == i
                                ? [
                                    BoxShadow(
                                      color: kidColors[i].withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Avatar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: List.generate(
                      kidEmojis.length,
                      (i) => GestureDetector(
                        onTap: () => setLocal(() => selectedEmoji = i),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: selectedEmoji == i
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedEmoji == i
                                  ? AppColors.primary
                                  : Colors.transparent,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              kidEmojis[i],
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'name': controller.text.trim(),
                'color': kidColors[selectedColor].toARGB32().toRadixString(16),
                'emoji': kidEmojis[selectedEmoji],
              }),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result == null) {
      controller.dispose();
      return;
    }
    final name = result['name'];
    if (name == null || name.isEmpty) {
      controller.dispose();
      return;
    }
    try {
      final familyId = await _sessionService.getOrCreateFamily();
      await _sessionService.addChild(
        name,
        familyId,
        color: result['color'],
        emoji: result['emoji'],
      );
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add child: $e')));
      }
    }
    // The dialog controller is local-scope; without this the
    // TextEditingController + its listeners linger until the GC
    // sweeps the State closure. Easy to miss because the dialog
    // disappears and the leak is invisible, but it adds up across
    // many add/rename operations in a long session.
    controller.dispose();
  }

  Future<void> _editChild(Child child) async {
    final controller = TextEditingController(text: child.name);
    try {
      // Rebuild the dialog's Save button enabled state on every
      // keystroke so the parent gets instant feedback for invalid
      // input (empty, too long, whitespace-only).
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              final trimmed = controller.text.trim();
              final isValid =
                  trimmed.isNotEmpty && trimmed.length <= _maxChildNameLength;
              return AlertDialog(
                title: const Text('Rename Child'),
                content: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: "Child's Name",
                    counterText: '${trimmed.length}/$_maxChildNameLength',
                    errorText: trimmed.isEmpty
                        ? null
                        : trimmed.length > _maxChildNameLength
                        ? 'Name is too long'
                        : null,
                  ),
                  autofocus: true,
                  maxLength: _maxChildNameLength,
                  onChanged: (_) => setLocal(() {}),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: isValid
                        ? () => Navigator.pop(ctx, trimmed)
                        : null,
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (name != null && name.isNotEmpty) {
        // renameChild + _loadAll can throw (RLS hiccup, network
        // drop). Without try/finally the controller would leak on
        // every rename that hits a server error.
        await _sessionService.renameChild(child.id, name);
        await _loadAll();
      }
    } finally {
      // Dialog controller is local-scope; dispose so the
      // TextEditingController and its listeners are released when
      // the dialog closes (success, cancel, or throw). Without this,
      // a long parent session that renames a kid several times leaks
      // one controller per rename.
      controller.dispose();
    }
  }

  Future<void> _deleteChild(Child child) async {
    // Pull the kid-device count before showing the dialog so the
    // parent can see "you're also about to unpair a device" *before*
    // the type-to-confirm gate. Without this, a parent could delete
    // a child and silently kill their kid's paired device.
    int pairedDevices = 0;
    String? firstDeviceName;
    try {
      final devices = await _kidDeviceService.listDevicesForChild(child.id);
      // Active = not revoked. Revoked devices are already
      // disconnected so they don't add to the warning.
      final active = devices.where((d) => !d.isRevoked).toList();
      pairedDevices = active.length;
      firstDeviceName = active.isEmpty ? null : active.first.deviceName;
    } catch (_) {}
    if (!mounted) return;

    final warningText = pairedDevices == 0
        ? null
        : pairedDevices == 1
        ? '${child.name}\'s paired device (${firstDeviceName ?? "unlabeled"}) '
              'will be unpaired. The kid will need to re-pair on their phone.'
        : '${child.name} has $pairedDevices paired devices. All of them '
              'will be unpaired — the kid will need to re-pair each device.';

    if (!mounted) return;
    // Capture messenger BEFORE the destructive dialog so the catch
    // block below can show a snackbar without tripping
    // use_build_context_synchronously (we'd otherwise be reading
    // `context` after a real network round-trip on the dialog).
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: 'Delete ${child.name}?',
      description:
          'This will permanently remove ${child.name}\'s:\n'
          '  • Homework sessions and proofs\n'
          '  • Tasks and proof images\n'
          '  • Recurring schedules\n'
          '  • Session stats and streak history\n\n'
          'This cannot be undone.',
      confirmPhrase: child.name,
      confirmButtonLabel: 'Delete forever',
      warningText: warningText,
    );
    if (!confirmed) return;
    try {
      await _sessionService.deleteChild(child.id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Couldn't delete ${child.name}: $e"),
          backgroundColor: AppColors.danger,
        ),
      );
    }
    if (mounted) await _loadAll();
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  /// Resolves the active session id for [childId] and pushes the
  /// LockActiveScreen so the parent can answer pending break
  /// requests inline. If the lock ended between the dashboard
  /// fetch and this tap (rare, but possible — dashboard polls
  /// every ~30s), the chip just silently does nothing.
  Future<void> _openActiveLockForBreaks(String childId) async {
    try {
      final session = await _sessionService.getActiveSession(childId);
      if (!mounted || session == null) return;
      // HomeworkSession only carries child_id; resolve the name
      // from the in-memory child list to avoid an extra round-trip.
      final childName = _children
          .firstWhere(
            (c) => c.id == session.childId,
            orElse: () => const Child(id: '', name: 'Child'),
          )
          .name;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              LockActiveScreen(sessionId: session.id, childName: childName),
        ),
      ).then((_) => _loadAll());
    } catch (_) {
      // Non-fatal: chip is a navigation shortcut, not a critical path.
    }
  }

  /// Opens the active LockActiveScreen for [childId] (used by the
  /// "View lock" primary action). Resolves the session on tap so the
  /// dashboard doesn't have to keep the full session object around.
  Future<void> _openActiveLock(String childId, String childName) async {
    final session = await _sessionService.getActiveSession(childId);
    if (session != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              LockActiveScreen(sessionId: session.id, childName: childName),
        ),
      ).then((_) => _loadAll());
    }
  }

  // ── Bottom-nav destinations ──────────────────────────────────────
  // No cross-tab scaffold exists in the app yet, so the non-Home tabs
  // push their nearest existing surface. Activity is per-child, so it
  // opens the first kid's Activity; Family opens the device/pairing
  // hub; Settings is PIN-gated.
  void _openActivityTab() {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a kid to see activity.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionStatsScreen(childName: _children.first.name),
      ),
    );
  }

  void _openFamilyTab() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KidDevicePairingScreen()),
    ).then((_) => _loadAll());
  }

  void _openSettingsTab() =>
      PinGuard.push(context, destination: const SettingsScreen());

  void _openNotifications() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
  ).then((_) => _loadAll());

  /// Small account sheet reachable from the header avatar. Keeps the
  /// sign-out action one tap away without cluttering the mock header.
  void _openAccountSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(ctx);
                _openSettingsTab();
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.logOut, color: AppColors.danger),
              title: Text(
                'Sign out',
                style: AppText.body(
                  color: AppColors.danger,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// "Tuesday · 3:40 PM" header eyebrow.
  String _nowLabel() {
    final now = DateTime.now();
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final day = days[now.weekday - 1];
    var h = now.hour % 12;
    if (h == 0) h = 12;
    final m = now.minute.toString().padLeft(2, '0');
    final ap = now.hour < 12 ? 'AM' : 'PM';
    return '$day · $h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    return ConsentGate(
      child: Scaffold(
        backgroundColor: AppColors.paper,
        bottomNavigationBar: _bottomNav(),
        body: SafeArea(
          bottom: false,
          child: KidDeviceEventToastListener(
            child: _loading
                ? const DashboardShimmer()
                : RefreshIndicator(
                    onRefresh: _loadAll,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                      children: [
                        _header(),
                        const SizedBox(height: 18),
                        if (_children.isEmpty)
                          _emptyKids()
                        else ...[
                          _planChip(),
                          const SizedBox(height: 24),
                          DfSectionLabel(
                            'Your kids',
                            trailing: GestureDetector(
                              onTap: _addChild,
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                'Manage',
                                style: AppText.button(
                                  color: AppColors.green,
                                  size: 13,
                                ),
                              ),
                            ),
                          ),
                          if (_hasUnpairedChildren) ...[
                            KidDeviceSetupHintCard(
                              firstChildId: _children.isNotEmpty
                                  ? _children.first.id
                                  : null,
                            ),
                            const SizedBox(height: 12),
                          ],
                          ..._children.map(
                            (child) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildChildCard(child),
                            ),
                          ),
                          const SizedBox(height: 2),
                          DfButton.outline(
                            'Add another kid',
                            icon: LucideIcons.userPlus,
                            onPressed: _addChild,
                          ),
                          const SizedBox(height: 24),
                          if (_todaySchedules.isNotEmpty) ...[
                            const DfSectionLabel("Today's schedule"),
                            _todayScheduleCard(),
                            const SizedBox(height: 24),
                          ],
                          const RecentKidDeviceActivityCard(),
                          const SizedBox(height: 24),
                          _statsSection(),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────
  Widget _header() {
    final email = _auth.currentUser?.email;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_nowLabel(), style: AppText.label()),
              const SizedBox(height: 8),
              Text('Home', style: AppText.display(size: 30)),
            ],
          ),
        ),
        _headerIconButton(
          LucideIcons.bell,
          onTap: _openNotifications,
          badge: _unreadNotifications,
        ),
        const SizedBox(width: 4),
        _headerIconButton(LucideIcons.settings, onTap: _openSettingsTab),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _openAccountSheet,
          behavior: HitTestBehavior.opaque,
          child: DfAvatar(email ?? 'You', size: 40, circle: true),
        ),
      ],
    );
  }

  Widget _headerIconButton(
    IconData icon, {
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.iconTile),
              border: Border.all(color: AppColors.borderCol),
            ),
            child: Icon(icon, size: 19, color: AppColors.ink),
          ),
          if (badge > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Plan chip ────────────────────────────────────────────────────
  Widget _planChip() {
    final left = (UpgradeScreen.freeLimit - _monthlySessionCount).clamp(
      0,
      9999,
    );
    return DfCard(
      color: AppColors.ink,
      borderColor: AppColors.ink,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UpgradeScreen()),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.sparkles, size: 18, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Free · $left of ${UpgradeScreen.freeLimit} sessions left this month',
              style: AppText.body(size: 13, color: Colors.white),
            ),
          ),
          Text(
            'Upgrade →',
            style: AppText.button(color: AppColors.gold, size: 13),
          ),
        ],
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────
  Widget _emptyKids() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: DfEmptyState(
        icon: LucideIcons.userPlus,
        title: 'Add your first kid to get started',
        hint: 'You can always add more later.',
        ctaLabel: 'Add a kid',
        onCta: _addChild,
      ),
    );
  }

  // ── Kid card ─────────────────────────────────────────────────────
  Widget _buildChildCard(Child child) {
    final childId = child.id;
    final childName = child.name;
    final hasActiveLock = _activeLocks[childId] ?? false;
    final pendingProofs = _pendingProofs[childId] ?? 0;
    final pendingBreaks = _pendingBreaks[childId] ?? 0;

    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: () => _showChildActions(child),
                child: _ChildAvatar(child: child),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            childName,
                            style: AppText.cardHeader(size: 17),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        hasActiveLock
                            ? const DfStatusPill(
                                'Focusing',
                                tone: DfPillTone.success,
                                dot: true,
                              )
                            : const DfStatusPill(
                                'Free time',
                                tone: DfPillTone.neutral,
                                dot: true,
                              ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasActiveLock
                          ? 'Focus session in progress'
                          : 'No session running',
                      style: AppText.bodySecondary(size: 13),
                    ),
                    Builder(
                      builder: (context) {
                        // Map the kid_devices_with_child view's status
                        // enum to a coloured dot + short label. null =
                        // no paired device at all.
                        final deviceStatus = _kidDeviceStatus[childId];
                        final status = deviceStatus?.status;
                        final lastSeen = deviceStatus?.lastSeenAt;
                        return KidDeviceStatusCaption(
                          status: status,
                          lastSeenAt: lastSeen,
                          onPair: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => KidDevicePairingScreen(
                                preselectChildId: childId,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (child.streakCount > 0) ...[
                      const SizedBox(height: 8),
                      _streakChip(child),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Pending-proof inbox banner.
          if (pendingProofs > 0) ...[
            const SizedBox(height: 12),
            _attentionBanner(
              icon: LucideIcons.inbox,
              tone: DfPillTone.attention,
              label:
                  '$pendingProofs ${pendingProofs == 1 ? 'proof' : 'proofs'} to review',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PendingProofsScreen(
                    childId: childId,
                    childName: childName,
                  ),
                ),
              ).then((_) => _loadAll()),
            ),
          ],
          // Pending-break banner — only meaningful with a live lock.
          if (pendingBreaks > 0) ...[
            const SizedBox(height: 8),
            _attentionBanner(
              icon: LucideIcons.coffee,
              tone: DfPillTone.attention,
              label:
                  '$pendingBreaks ${pendingBreaks == 1 ? 'break request' : 'break requests'} waiting',
              onTap: () => _openActiveLockForBreaks(childId),
            ),
          ],

          const SizedBox(height: 14),
          // Primary actions row.
          Row(
            children: [
              Expanded(
                child: DfButton.outline(
                  'Kid view',
                  icon: LucideIcons.eye,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          KidHomeScreen(childId: childId, childName: childName),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: pendingProofs > 0
                    ? DfButton(
                        'Review',
                        icon: LucideIcons.clipboardCheck,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PendingProofsScreen(
                              childId: childId,
                              childName: childName,
                            ),
                          ),
                        ).then((_) => _loadAll()),
                      )
                    : hasActiveLock
                    ? DfButton.ink(
                        'View lock',
                        icon: LucideIcons.clock,
                        onPressed: () => _openActiveLock(childId, childName),
                      )
                    : DfButton(
                        'Start',
                        icon: LucideIcons.lock,
                        onPressed: () => PinGuard.push(
                          context,
                          destination: LockConfigScreen(
                            childId: childId,
                            childName: childName,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 6),
          // Secondary quick actions — kept complete so nothing the old
          // dashboard reached is lost.
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _quickAction(
                LucideIcons.history,
                'History',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProofReviewScreen(childId: childId),
                  ),
                ),
              ),
              _quickAction(
                LucideIcons.bookOpen,
                'Homework',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChildHomeworkScreen(
                      childId: childId,
                      childName: childName,
                    ),
                  ),
                ),
              ),
              _quickAction(
                LucideIcons.chartColumn,
                'Stats',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionStatsScreen(childName: childName),
                  ),
                ),
              ),
              _quickAction(
                LucideIcons.calendar,
                'Schedule',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SchedulesScreen(childId: childId, childName: childName),
                  ),
                ),
              ),
              _quickAction(
                LucideIcons.image,
                'Gallery',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProofGalleryScreen(
                      childId: childId,
                      childName: childName,
                    ),
                  ),
                ),
              ),
              _quickAction(
                LucideIcons.user,
                'Profile',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KidProfileScreen(child: child),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _streakChip(Child child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.amberTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.flame, size: 13, color: AppColors.amber),
          const SizedBox(width: 5),
          Text(
            '${child.streakCount} day streak',
            style: AppText.caption(
              color: AppColors.amberDeep,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          if (child.lastStreakDate != null &&
              !_streakIsToday(child.lastStreakDate!))
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Text(
                '(at risk)',
                style: AppText.caption(
                  size: 11,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }

  Widget _attentionBanner({
    required IconData icon,
    required DfPillTone tone,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.amberTint,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          border: Border.all(color: AppColors.amberTint2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.amberDeep),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppText.body(
                  size: 13,
                  color: AppColors.amberDeep,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.amberDeep,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.ink70),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.body(
                size: 13,
                color: AppColors.ink70,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press sheet on a kid avatar — rename / pair / delete.
  void _showChildActions(Child child) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.pencil),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _editChild(child);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.smartphone),
              title: const Text('Pair kid device'),
              subtitle: Text(
                'Generate a code for ${child.name}’s phone',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        KidDevicePairingScreen(preselectChildId: child.id),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: AppColors.danger),
              title: Text(
                'Delete',
                style: AppText.body(color: AppColors.danger),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteChild(child);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Today's schedule ─────────────────────────────────────────────
  Widget _todayScheduleCard() {
    return DfCard(
      child: Column(
        children: [
          for (var i = 0; i < _todaySchedules.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            _scheduleRow(_todaySchedules[i]),
          ],
        ],
      ),
    );
  }

  Widget _scheduleRow(RecurringSchedule s) {
    final child = _children.firstWhere(
      (c) => c.id == s.childId,
      orElse: () => const Child(id: '', name: 'Child'),
    );
    final childName = child.name;
    final childId = s.childId;
    final hasActive = _activeLocks[childId] ?? false;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.greenTint,
            borderRadius: BorderRadius.circular(AppRadius.iconTile),
          ),
          child: const Icon(
            LucideIcons.calendarDays,
            size: 18,
            color: AppColors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$childName · Homework', style: AppText.listTitle(size: 15)),
              const SizedBox(height: 2),
              Text(
                '${s.durationMinutes} min session',
                style: AppText.bodySecondary(size: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (hasActive)
          const DfStatusPill('Active', tone: DfPillTone.success, dot: true)
        else
          DfButton(
            'Start now',
            expand: false,
            onPressed: () => PinGuard.push(
              context,
              destination: LockConfigScreen(
                childId: childId,
                childName: childName,
                // Pre-fill from the schedule so the parent doesn't
                // re-pick what the schedule already says.
                initialMinLock: s.durationMinutes,
                initialApprovalMode: s.approvalMode,
              ),
            ).then((_) => _loadAll()),
          ),
      ],
    );
  }

  // ── This-month stats ─────────────────────────────────────────────
  Widget _statsSection() {
    if (_totalSessions <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DfSectionLabel('This month'),
        DfCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DfStatTile(
                      '$_totalSessions',
                      'sessions',
                      align: CrossAxisAlignment.center,
                    ),
                  ),
                  const _StatDivider(),
                  Expanded(
                    child: DfStatTile(
                      '${_totalMinutes}m',
                      'focused',
                      align: CrossAxisAlignment.center,
                    ),
                  ),
                  const _StatDivider(),
                  Expanded(
                    child: DfStatTile(
                      '$_totalApproved',
                      'approved',
                      valueColor: AppColors.green,
                      align: CrossAxisAlignment.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    LucideIcons.bot,
                    size: 15,
                    color: _mistralCallsToday >= 40
                        ? AppColors.danger
                        : AppColors.ink45,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$_mistralCallsToday / 50 AI checks today',
                    style: AppText.caption(
                      color: _mistralCallsToday >= 40
                          ? AppColors.danger
                          : AppColors.ink45,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Bottom tab bar ───────────────────────────────────────────────
  Widget _bottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.borderCol)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              _navItem(LucideIcons.house, 'Home', selected: true, onTap: () {}),
              _navItem(
                LucideIcons.activity,
                'Activity',
                onTap: _openActivityTab,
              ),
              _navItem(LucideIcons.users, 'Family', onTap: _openFamilyTab),
              _navItem(
                LucideIcons.settings,
                'Settings',
                onTap: _openSettingsTab,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    IconData icon,
    String label, {
    bool selected = false,
    required VoidCallback onTap,
  }) {
    final color = selected ? AppColors.green : AppColors.ink45;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppText.caption(color: color).copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A streak is "today" if last_streak_date is today OR yesterday.
  /// We give a one-day grace period because the user might open the
  /// app mid-day before the kid has done their session yet today —
  /// showing "(at risk)" at 7am would be wrong. By "yesterday" we
  /// mean: if the kid hasn't done today's session yet, the streak is
  /// still safe to show as active; the "at risk" warning only
  /// appears once the streak is actually broken.
  bool _streakIsToday(DateTime lastStreakDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime(
      lastStreakDate.year,
      lastStreakDate.month,
      lastStreakDate.day,
    );
    final diff = today.difference(last).inDays;
    return diff == 0 || diff == 1;
  }
}

/// Renders a child's avatar using their emoji + chosen color when
/// present, falling back to the legacy first-letter look for kids who
/// were added before this feature shipped.
class _ChildAvatar extends StatelessWidget {
  final Child child;
  const _ChildAvatar({required this.child});

  @override
  Widget build(BuildContext context) {
    final hasCustomization = child.emoji != null || child.color != null;
    // Kids who never picked a custom emoji/color get the canonical
    // sage-forest monogram (rounded-square, forest initial). Kids who
    // chose an emoji keep it — but rendered in the same rounded-square
    // tile shape so the row reads as one system.
    if (!hasCustomization) {
      return MonogramAvatar.parent(name: child.name, size: 46);
    }

    Color? color;
    if (child.color != null) {
      final parsed = int.tryParse(child.color!, radix: 16);
      if (parsed != null) {
        color = Color(parsed);
      }
    }
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: (color ?? AppColors.forest).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.monogram),
      ),
      alignment: Alignment.center,
      child: Text(
        child.emoji ?? (child.name.isEmpty ? '?' : child.name[0].toUpperCase()),
        style: const TextStyle(fontSize: 24),
      ),
    );
  }
}

/// 1px vertical hairline separating the three family-stat tiles,
/// matching the redesign's "tiles split by vertical hairlines" spec.
class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: AppColors.line);
}
