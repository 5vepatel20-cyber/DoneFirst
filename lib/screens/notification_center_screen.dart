import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final _notificationService = NotificationService();
  List<Map<String, dynamic>> _notifications = [];
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
    await _load();
  }

  Future<void> _markAllRead() async {
    await _notificationService.markAllAsRead();
    await _load();
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
          if (_notifications.any((n) => n['read'] == false))
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none,
              title: 'No notifications',
              subtitle: 'Activity appears here',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _notifications.length,
              itemBuilder: (ctx, i) {
                final n = _notifications[i];
                final type = n['type'] as String? ?? '';
                final isRead = n['read'] == true;
                return Dismissible(
                  key: Key(n['id']),
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
                  onDismissed: (_) {},
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isRead ? null : AppColors.primary.withOpacity(0.03),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _colorForType(type).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _iconForType(type),
                          color: _colorForType(type),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        n['title'] ?? '',
                        style: TextStyle(
                          fontWeight: isRead
                              ? FontWeight.normal
                              : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: n['body'] != null
                          ? Text(
                              n['body'],
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
                      onTap: () => _markRead(n['id']),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
