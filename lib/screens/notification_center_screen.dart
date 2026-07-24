import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../models/models.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final _notificationService = NotificationService();
  List<AppNotification> _notifications = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notifications = await _notificationService.getNotifications();
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _loading = false;
        });
      }
    } catch (e) {
      // Without this catch a transient Supabase hiccup would leave the
      // spinner running forever — same shape as the other rebuilt
      // screens' _load guards.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _markRead(String id) async {
    // Snapshot the in-memory row BEFORE the network call so we can
    // restore it if the write fails — without this, a Supabase hiccup
    // would silently leave the dot cleared in UI but `read=false`
    // server-side, and the next _load() would resurrect the unread dot.
    final i = _notifications.indexWhere((n) => n.id == id);
    final original = i >= 0 ? _notifications[i] : null;
    try {
      await _notificationService.markAsRead(id);
      if (!mounted) return;
      setState(() {
        if (i >= 0 && original != null) {
          _notifications[i] = AppNotification(
            id: original.id,
            parentId: original.parentId,
            childId: original.childId,
            type: original.type,
            title: original.title,
            body: original.body,
            read: true,
            createdAt: original.createdAt,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t mark as read: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _notificationService.markAllAsRead();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t mark all read: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _delete(String id) async {
    // Snapshot the in-memory row BEFORE the dismiss so we can
    // restore it if the Supabase delete fails. Same reasoning as
    // _markRead — without the restore path the next pull-to-refresh
    // would resurrect a row the user thinks they dismissed.
    final i = _notifications.indexWhere((n) => n.id == id);
    final original = i >= 0 ? _notifications[i] : null;
    // Dismiss-then-delete so the row leaves the UI immediately
    // rather than snapping back if the delete is slow.
    setState(() => _notifications.removeWhere((n) => n.id == id));
    try {
      await _notificationService.deleteNotification(id);
    } catch (e) {
      if (!mounted) return;
      // Restore the row at its original index so the list feels
      // honest about what actually persisted.
      if (original != null) {
        setState(() {
          _notifications.insert(i.clamp(0, _notifications.length), original);
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t delete notification: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text(
          'This removes every notification in this list. It can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _notificationService.clearAll();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t clear notifications: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'proof_submitted':
        return LucideIcons.camera;
      case 'break_requested':
        return LucideIcons.coffee;
      case 'break_granted':
        return LucideIcons.cupSoda;
      case 'session_complete':
        return LucideIcons.checkCircle2;
      default:
        return LucideIcons.bell;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'proof_submitted':
        return AppColors.infoFg;
      case 'break_requested':
        return AppColors.amber;
      case 'break_granted':
        return AppColors.green;
      case 'session_complete':
        return AppColors.green;
      default:
        return AppColors.green;
    }
  }

  /// "Today" / "Earlier" grouping — mirrors the Activity mock's
  /// day-based sectioning so the list doesn't read as one flat wall.
  String _groupLabel(DateTime d) {
    final now = DateTime.now();
    final isToday =
        d.year == now.year && d.month == now.month && d.day == now.day;
    return isToday ? 'Today' : 'Earlier';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => !n.read);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.trash2, size: 20),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError(_error!);
    if (_notifications.isEmpty) return _buildEmpty();
    return _buildList();
  }

  Widget _buildLoading() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DfCard(
            color: AppColors.border2,
            borderColor: AppColors.border2,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.borderCol,
                    borderRadius: BorderRadius.circular(AppRadius.iconTile),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12,
                        width: 140,
                        color: AppColors.borderCol,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 90,
                        color: AppColors.borderCol,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        const SizedBox(height: 60),
        DfCard(
          child: Column(
            children: [
              const Icon(
                LucideIcons.wifiOff,
                color: AppColors.dangerFg,
                size: 28,
              ),
              const SizedBox(height: 10),
              Text(
                'Couldn\'t load notifications',
                style: AppText.cardHeader(size: 16),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.body(size: 13),
              ),
              const SizedBox(height: 16),
              DfButton.outline(
                'Try again',
                icon: LucideIcons.refreshCw,
                onPressed: _load,
                expand: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        DfEmptyState(
          icon: LucideIcons.bellOff,
          title: 'No notifications yet',
          hint: 'Proofs, breaks and session updates will show up here.',
        ),
      ],
    );
  }

  Widget _buildList() {
    // Group by day while preserving the service's most-recent-first
    // order within each group.
    final groups = <String, List<AppNotification>>{};
    for (final n in _notifications) {
      groups.putIfAbsent(_groupLabel(n.createdAt), () => []).add(n);
    }
    final order = ['Today', 'Earlier']..retainWhere(groups.containsKey);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final label in order) ...[
          DfSectionLabel(label),
          ...groups[label]!.map(
            (n) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NotificationRow(
                notification: n,
                icon: _iconForType(n.type),
                color: _colorForType(n.type),
                onTap: () => _markRead(n.id),
                onDismiss: () => _delete(n.id),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final AppNotification notification;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationRow({
    required this.notification,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = notification.read;
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.dangerFg,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Icon(LucideIcons.trash2, color: Colors.white),
      ),
      onDismissed: (_) => onDismiss(),
      child: DfCard(
        onTap: onTap,
        color: isRead ? AppColors.card : AppColors.greenTint,
        borderColor: isRead
            ? AppColors.borderCol
            : AppColors.green.withValues(alpha: 0.35),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.iconTile),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: AppText.listTitle(size: 14).copyWith(
                      fontWeight: isRead ? FontWeight.w500 : FontWeight.w800,
                    ),
                  ),
                  if (notification.body != null) ...[
                    const SizedBox(height: 3),
                    Text(notification.body!, style: AppText.caption()),
                  ],
                ],
              ),
            ),
            if (!isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
