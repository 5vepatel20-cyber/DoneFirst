import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../services/notification_service.dart';
import '../services/schedule_service.dart';
import '../services/proof_service.dart';
import '../services/kid_device_service.dart';
import '../main.dart' as app;
import '../theme/app_theme.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/consent_gate.dart';
import '../widgets/pin_guard.dart';
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

class ParentDashboard extends StatefulWidget {
  const ParentDashboard({super.key});

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  final _auth = AuthService();
  final _sessionService = SessionService();
  final _notificationService = NotificationService();
  final _scheduleService = ScheduleService();
  final _proofService = ProofService();
  final _kidDeviceService = KidDeviceService();
  List<Child> _children = [];
  final Map<String, bool> _activeLocks = {};
  final Map<String, int> _pendingProofs = {};
  /// kid-device status per child for the dashboard's per-row dot.
  /// null = no paired device for that child, otherwise the derived
  /// status string ('online' / 'recent' / 'stale' / 'revoked').
  final Map<String, String?> _kidDeviceStatus = {};
  bool _loading = true;
  int _monthlySessionCount = 0;
  int _unreadNotifications = 0;
  int _totalSessions = 0;
  int _totalMinutes = 0;
  int _totalApproved = 0;
  int _mistralCallsToday = 0;
  List<RecurringSchedule> _todaySchedules = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
    app.realtimeService.startListening();
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
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await _sessionService.getOrCreateFamily();
      final children = await _sessionService.getChildren(_auth.currentUser!.id);
      setState(() => _children = children);

      // Fan-out: monthly count, mistral usage, unread notifications,
      // today's schedules, and the parent's family_id are all
      // independent reads. Fire them in parallel so the dashboard
      // loads in max(latencies) instead of sum(latencies).
      final parentId = _auth.currentUser!.id;
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

      // Per-child loads run in parallel instead of serial. Each
      // child is independent (active-session check + pending-proofs
      // count + kid-device status), so there's no reason to wait
      // for child A before starting child B. For a 3-kid family
      // this drops three round-trip pairs to one parallel batch.
      final perChild = await Future.wait(
        _children.map((child) async {
          final session =
              await _sessionService.getActiveSession(child.id);
          int pending = _pendingProofs[child.id] ?? 0;
          // Pending-proof count per child for the inbox chip. If this
          // throws (e.g. RLS still pending), leave the prior value
          // alone rather than wipe it to 0.
          try {
            final proofs =
                await _proofService.getPendingProofs(child.id);
            pending = proofs.length;
          } catch (_) {}
          // Kid-device status for the dashboard dot. Failures
          // collapse to null (no device) so a transient RLS hiccup
          // never breaks the row.
          String? deviceStatus;
          try {
            final devices =
                await _kidDeviceService.listDevicesForChild(child.id);
            if (devices.isNotEmpty) {
              deviceStatus = devices.first.status;
            }
          } catch (_) {}
          return MapEntry(
            child.id,
            (session != null, pending, deviceStatus),
          );
        }),
      );
      for (final entry in perChild) {
        _activeLocks[entry.key] = entry.value.$1;
        _pendingProofs[entry.key] = entry.value.$2;
        _kidDeviceStatus[entry.key] = entry.value.$3;
      }
    } catch (_) {}
    setState(() => _loading = false);
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
                        color: kidColors[selectedColor]
                            .withValues(alpha: 0.15),
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
                                ? Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  )
                                : null,
                            boxShadow: selectedColor == i
                                ? [
                                    BoxShadow(
                                      color: kidColors[i]
                                          .withValues(alpha: 0.5),
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
                'color': kidColors[selectedColor]
                    .toARGB32()
                    .toRadixString(16),
                'emoji': kidEmojis[selectedEmoji],
              }),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final name = result['name'];
    if (name == null || name.isEmpty) return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add child: $e')),
        );
      }
    }
  }

  Future<void> _editChild(Child child) async {
    final controller = TextEditingController(
      text: child.name,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Child'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Child's Name"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _sessionService.renameChild(child.id, name);
      await _loadAll();
    }
  }

  Future<void> _deleteChild(Child child) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Child?'),
        content: Text(
          'All data for "${child.name}" will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _sessionService.deleteChild(child.id);
      await _loadAll();
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ConsentGate(
      child: Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.sprout,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'DoneFirst',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
            tooltip: 'Refresh',
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationCenterScreen(),
                  ),
                ).then((_) => _loadAll()),
                tooltip: 'Notifications',
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '$_unreadNotifications',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => PinGuard.push(
              context,
              destination: const SettingsScreen(),
            ),
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: _loading
          ? const DashboardShimmer()
          : _children.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha:0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Add your first child to get started',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You can always add more later',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _addChild,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add Child'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: AppColors.accent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$_monthlySessionCount / ${UpgradeScreen.freeLimit} free sessions this month',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (_monthlySessionCount >= UpgradeScreen.freeLimit)
                            FilledButton.tonal(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const UpgradeScreen()),
                              ),
                              child: const Text('Upgrade'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // AI usage card — shows how many Mistral verification
                  // calls the parent has made in the last 24h. Parents
                  // who hit the daily cap get an explanation of why
                  // proofs aren't being auto-approved.
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.smart_toy,
                        size: 16,
                        color: _mistralCallsToday >= 40
                            ? AppColors.danger
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_mistralCallsToday / 50 AI checks today',
                        style: TextStyle(
                          fontSize: 12,
                          color: _mistralCallsToday >= 40
                              ? AppColors.danger
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (_totalSessions > 0) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _miniStat(
                              Icons.play_circle,
                              '$_totalSessions',
                              'Sessions',
                            ),
                            _miniStat(Icons.timer, '${_totalMinutes}m', 'Time'),
                            _miniStat(
                              Icons.verified,
                              '$_totalApproved',
                              'Approved',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_todaySchedules.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: AppColors.primary.withValues(alpha:0.04),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.today,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  "Today's Schedule",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._todaySchedules.map((s) {
                              final child = _children.firstWhere(
                                (c) => c.id == s.childId,
                                orElse: () => const Child(id: '', name: 'Child'),
                              );
                              final childName = child.name;
                              final childId = s.childId;
                              final hasActive = _activeLocks[childId] ?? false;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$childName - ${s.durationMinutes}m',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    if (!hasActive)
                                      TextButton(
                                        onPressed: () {
                                          PinGuard.push(
                                            context,
                                            destination: LockConfigScreen(
                                              childId: childId,
                                              childName: childName,
                                              // Pre-fill from the
                                              // schedule so the parent
                                              // doesn't re-pick what the
                                              // schedule already says.
                                              initialMinLock: s.durationMinutes,
                                              initialApprovalMode: s.approvalMode,
                                            ),
                                          ).then((_) => _loadAll());
                                        },
                                        child: const Text('Start Now'),
                                      )
                                    else
                                      const Text(
                                        'Already active',
                                        style: TextStyle(
                                          color: AppColors.success,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ..._children.map((child) => _buildChildCard(child)),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: _addChild,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add Another Child'),
                    ),
                  ),
                ],
              ),
            ),
    ),
    );
  }

  Widget _buildChildCard(Child child) {
    final childId = child.id;
    final childName = child.name;
    final hasActiveLock = _activeLocks[childId] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onLongPress: () => showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.edit),
                            title: const Text('Rename'),
                            onTap: () {
                              Navigator.pop(ctx);
                              _editChild(child);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.smartphone),
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
                                  builder: (_) => KidDevicePairingScreen(
                                    preselectChildId: child.id,
                                  ),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(
                              Icons.delete,
                              color: AppColors.danger,
                            ),
                            title: Text(
                              'Delete',
                              style: TextStyle(color: AppColors.danger),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              _deleteChild(child);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: _ChildAvatar(child: child),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        childName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hasActiveLock
                                  ? AppColors.accent
                                  : AppColors.success,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasActiveLock ? 'Lock Active' : 'No Active Lock',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasActiveLock
                                  ? AppColors.accent
                                  : AppColors.success,
                            ),
                          ),
                        ],
                      ),
                      Builder(builder: (context) {
                        // Map the kid_devices_with_child view's
                        // status enum to a coloured dot + short label.
                        // null = no paired device at all.
                        final status = _kidDeviceStatus[childId];
                        final (color, label) = switch (status) {
                          'online' => (AppColors.grass, 'Device online'),
                          'recent' => (AppColors.warn, 'Device idle'),
                          'stale' => (AppColors.muted, 'Device offline'),
                          'revoked' => (AppColors.danger, 'Device revoked'),
                          _ => (AppColors.disabled, 'No device paired'),
                        };
                        return Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: color == AppColors.disabled
                                      ? AppColors.faint
                                      : AppColors.ink2,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (child.streakCount > 0) ...[
                        const SizedBox(height: 2),
                        // Streak chip. Hidden when 0 so we never
                        // display a discouraging "0 day streak" to
                        // a kid who hasn't started yet.
                        Row(
                          children: [
                            const Text('🔥', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text(
                              '${child.streakCount} day streak',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (child.lastStreakDate != null &&
                                !_streakIsToday(child.lastStreakDate!))
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  '(at risk)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary
                                        .withValues(alpha: 0.8),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // Pending-proof inbox banner. Hidden when 0 so we never
            // say "0 to review" — empty state is the inbox-zero card
            // on the screen itself.
            if ((_pendingProofs[childId] ?? 0) > 0) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PendingProofsScreen(
                      childId: childId,
                      childName: childName,
                    ),
                  ),
                ).then((_) => _loadAll()),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inbox,
                        size: 18,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_pendingProofs[childId]} ${_pendingProofs[childId] == 1 ? 'proof' : 'proofs'} to review',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: AppColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => KidHomeScreen(
                          childId: childId,
                          childName: childName,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Kid View'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: hasActiveLock
                      ? FilledButton.icon(
                          onPressed: () async {
                            final session = await _sessionService
                                .getActiveSession(childId);
                            if (session != null && mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LockActiveScreen(
                                    sessionId: session.id,
                                    childName: childName,
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.pending, size: 18),
                          label: const Text('View Lock'),
                        )
                      : FilledButton.icon(
                          onPressed: () => PinGuard.push(
                            context,
                            destination: LockConfigScreen(
                              childId: childId,
                              childName: childName,
                            ),
                          ),
                          icon: const Icon(Icons.lock, size: 18),
                          label: const Text('Start Lock'),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProofReviewScreen(childId: childId),
                    ),
                  ),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('History'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SessionStatsScreen(childName: childName),
                    ),
                  ),
                  icon: const Icon(Icons.analytics, size: 18),
                  label: const Text('Stats'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SchedulesScreen(
                        childId: childId,
                        childName: childName,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: const Text('Schedule'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProofGalleryScreen(
                        childId: childId,
                        childName: childName,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('Gallery'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KidProfileScreen(child: child),
                    ),
                  ),
                  icon: const Icon(Icons.face, size: 18),
                  label: const Text('Profile'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
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
    final hasCustomization =
        child.emoji != null || child.color != null;
    if (!hasCustomization) {
      return CircleAvatar(
        backgroundColor: AppColors.success.withValues(alpha: 0.1),
        child: Text(
          child.name.isEmpty ? '?' : child.name[0].toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.success,
          ),
        ),
      );
    }

    Color? color;
    if (child.color != null) {
      final parsed = int.tryParse(child.color!, radix: 16);
      if (parsed != null) {
        color = Color(parsed);
      }
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: (color ?? AppColors.primary).withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          child.emoji ?? child.name[0].toUpperCase(),
          style: const TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}
