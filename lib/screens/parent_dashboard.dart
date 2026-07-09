import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../services/notification_service.dart';
import '../services/schedule_service.dart';
import '../services/realtime_service.dart';
import '../main.dart' as app;
import '../theme/app_theme.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/consent_gate.dart';
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
  List<Child> _children = [];
  final Map<String, bool> _activeLocks = {};
  bool _loading = true;
  int _monthlySessionCount = 0;
  int _unreadNotifications = 0;
  int _totalSessions = 0;
  int _totalMinutes = 0;
  int _totalApproved = 0;
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

      _monthlySessionCount = await _sessionService.getMonthlySessionCount(
        _auth.currentUser!.id,
      );
      _unreadNotifications = await _notificationService.getUnreadCount();

      _todaySchedules = await _scheduleService.getTodaySchedules();

      final family = await Supabase.instance.client
          .from('parents')
          .select('family_id')
          .eq('id', _auth.currentUser!.id)
          .single();
      if (family['family_id'] != null) {
        final allChildren = await Supabase.instance.client
            .from('children')
            .select('id')
            .eq('family_id', family['family_id']);
        final childIds = allChildren.map((c) => c['id'] as String).toList();
        if (childIds.isNotEmpty) {
          final allSessions = await Supabase.instance.client
              .from('homework_sessions')
              .select('id, duration_minutes')
              .inFilter('child_id', childIds);
          _totalSessions = allSessions.length;
          _totalMinutes = allSessions.fold<int>(
            0,
            (sum, s) => sum + ((s['duration_minutes'] as int?) ?? 0),
          );
          final approvedProofs = await Supabase.instance.client
              .from('proof_submissions')
              .select('id')
              .eq('parent_decision', 'approved');
          _totalApproved = approvedProofs.length;
        }
      }

      for (final child in _children) {
        final session = await _sessionService.getActiveSession(
          child.id,
        );
        _activeLocks[child.id] = session != null;
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _addChild() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Child'),
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      try {
        final familyId = await _sessionService.getOrCreateFamily();
        await _sessionService.addChild(name, familyId);
        await _loadAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add child: $e')),
          );
        }
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
                Icons.check_circle_outline,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            const Text('DoneFirst'),
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
                                  builder: (_) => const UpgradeScreen(),
                                ),
                              ),
                              child: const Text('Upgrade'),
                            ),
                        ],
                      ),
                    ),
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
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => LockConfigScreen(
                                                childId: childId,
                                                childName: childName,
                                              ),
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
                  child: CircleAvatar(
                    backgroundColor: hasActiveLock
                        ? AppColors.accent.withValues(alpha:0.15)
                        : AppColors.success.withValues(alpha:0.1),
                    child: Text(
                      childName[0].toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: hasActiveLock
                            ? AppColors.accent
                            : AppColors.success,
                      ),
                    ),
                  ),
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
                    ],
                  ),
                ),
              ],
            ),
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
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LockConfigScreen(
                                childId: childId,
                                childName: childName,
                              ),
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
}
