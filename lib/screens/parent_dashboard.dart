import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
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

class ParentDashboard extends StatefulWidget {
  const ParentDashboard({super.key});

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  final _auth = AuthService();
  final _sessionService = SessionService();
  List<Map<String, dynamic>> _children = [];
  final Map<String, bool> _activeLocks = {};
  bool _loading = true;
  int _monthlySessionCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
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

      for (final child in children) {
        final sessions = await _sessionService.getActiveSession(
          child['id'] as String,
        );
        _activeLocks[child['id'] as String] = sessions.isNotEmpty;
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
      final familyId = await _sessionService.getOrCreateFamily();
      await _sessionService.addChild(name, familyId);
      await _loadAll();
    }
  }

  Future<void> _editChild(Map<String, dynamic> child) async {
    final controller = TextEditingController(
      text: child['name'] as String? ?? '',
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
      await _sessionService.renameChild(child['id'], name);
      await _loadAll();
    }
  }

  Future<void> _deleteChild(Map<String, dynamic> child) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Child?'),
        content: Text(
          'All data for "${child['name']}" will be permanently removed.',
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
      await _sessionService.deleteChild(child['id']);
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
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
          ? const Center(child: CircularProgressIndicator())
          : _children.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
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
    );
  }

  Widget _buildChildCard(Map<String, dynamic> child) {
    final childId = child['id'] as String;
    final childName = child['name'] as String? ?? 'Child';
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
                        ? AppColors.accent.withOpacity(0.15)
                        : AppColors.success.withOpacity(0.1),
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
                            final sessions = await _sessionService
                                .getActiveSession(childId);
                            if (sessions.isNotEmpty && mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LockActiveScreen(
                                    sessionId: sessions.first['id'] as String,
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
}
