import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notifications = await _notificationService.getNotifications();
    if (mounted) {
      setState(() {
        _notifications = notifications;
        _loading = false;
      });
    }
  }

  Future<void> _markRead(String id) async {
    await _notificationService.markAsRead(id);
    if (!mounted) return;
    setState(() {
      // Local flip avoids a full reload — the row already exists in
      // memory and there's no other state to recompute.
      final i = _notifications.indexWhere((n) => n.id == id);
      if (i >= 0) {
        _notifications[i] = AppNotification(
          id: _notifications[i].id,
          parentId: _notifications[i].parentId,
          childId: _notifications[i].childId,
          type: _notifications[i].type,
          title: _notifications[i].title,
          body: _notifications[i].body,
          read: true,
          createdAt: _notifications[i].createdAt,
        );
      }
    });
  }

  Future<void> _markAllRead() async {
    await _notificationService.markAllAsRead();
    await _load();
  }

  Future<void> _delete(String id) async {
    // Dismiss-then-delete so the row leaves the UI immediately
    // rather than snapping back if the delete is slow.
    setState(() => _notifications.removeWhere((n) => n.id == id));
    await _notificationService.deleteNotification(id);
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'proof_submitted':
        return Icons.camera_alt;
      case 'break_requested':
        return Icons.coffee;
      case 'break_granted':
        return Icons.coffee_outlined;
      case 'session_complete':
        return Icons.check_circle;
      default:
        return Icons.notifications;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'proof_submitted':
        return AppColors.info;
      case 'break_requested':
        return AppColors.accent;
      case 'break_granted':
        return AppColors.success;
      case 'session_complete':
        return AppColors.success;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_notifications.any((n) => !n.read))
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.notifications_none,
                    title: 'No notifications',
                    subtitle: 'Activity appears here',
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _notifications.length,
                itemBuilder: (ctx, i) {
                  final n = _notifications[i];
                  final type = n.type;
                  final isRead = n.read;
                  return Dismissible(
                    key: Key(n.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _delete(n.id),
                    child: Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isRead ? null : AppColors.primary.withValues(alpha:0.03),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _colorForType(type).withValues(alpha:0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _iconForType(type),
                          color: _colorForType(type),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        n.title,
                        style: TextStyle(
                          fontWeight: isRead
                              ? FontWeight.normal
                              : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: n.body != null
                          ? Text(
                              n.body!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            )
                          : null,
                      trailing: isRead
                          ? null
                          : Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                      onTap: () => _markRead(n.id),
                    ),
                  ),
                );
              },
            ),
          ),
    );
  }
}
