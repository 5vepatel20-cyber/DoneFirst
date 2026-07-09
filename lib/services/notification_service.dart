import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'notification_preferences_service.dart';

class NotificationService {
  final _supabase = Supabase.instance.client;
  final _prefs = NotificationPreferencesService();

  Future<void> insertNotification({
    required String parentId,
    String? childId,
    required String type,
    required String title,
    String? body,
  }) async {
    // Drop the row entirely if the parent has this type turned off.
    // Saves storage and means the bell badge never counts disabled
    // types — which is what parents expect.
    if (!await _prefs.isEnabled(type)) return;
    await _supabase.from('notifications').insert({
      'parent_id': parentId,
      'child_id': childId,
      'type': type,
      'title': title,
      'body': body,
      'read': false,
    });
  }

  Future<AppNotification> addNotification({
    required String childId,
    required String type,
    required String title,
    String? body,
  }) async {
    if (!await _prefs.isEnabled(type)) {
      // Returning a synthetic empty record would lie to the caller, so
      // we surface a clear error instead. Callers that need
      // fire-and-forget should use insertNotification.
      throw StateError(
        'Notification type "$type" is disabled in user preferences.',
      );
    }
    final response = await _supabase
        .from('notifications')
        .insert({
          'parent_id': _supabase.auth.currentUser!.id,
          'child_id': childId,
          'type': type,
          'title': title,
          if (body != null) 'body': body,
          'read': false,
        })
        .select()
        .single();
    return AppNotification.fromMap(response);
  }

  Future<List<AppNotification>> getNotifications() async {
    final response = await _supabase
        .from('notifications')
        .select()
        .eq('parent_id', _supabase.auth.currentUser!.id)
        .order('created_at', ascending: false);
    final prefs = await _prefs.getPrefs();
    return response
        .map((m) => AppNotification.fromMap(m))
        .where((n) => prefs[n.type] ?? true)
        .toList();
  }

  Future<List<AppNotification>> getUnreadNotifications() async {
    final response = await _supabase
        .from('notifications')
        .select()
        .eq('parent_id', _supabase.auth.currentUser!.id)
        .eq('read', false)
        .order('created_at', ascending: false);
    final prefs = await _prefs.getPrefs();
    return response
        .map((m) => AppNotification.fromMap(m))
        .where((n) => prefs[n.type] ?? true)
        .toList();
  }

  Future<void> markAsRead(String notificationId) async {
    await _supabase
        .from('notifications')
        .update({'read': true})
        .eq('id', notificationId);
  }

  Future<void> markAllAsRead() async {
    await _supabase
        .from('notifications')
        .update({'read': true})
        .eq('parent_id', _supabase.auth.currentUser!.id)
        .eq('read', false);
  }

  Future<void> deleteNotification(String notificationId) async {
    await _supabase
        .from('notifications')
        .delete()
        .eq('id', notificationId);
  }

  Future<void> clearAll() async {
    await _supabase
        .from('notifications')
        .delete()
        .eq('parent_id', _supabase.auth.currentUser!.id);
  }

  Future<int> getUnreadCount() async {
    final response = await _supabase
        .from('notifications')
        .select('id, type')
        .eq('parent_id', _supabase.auth.currentUser!.id)
        .eq('read', false);
    final prefs = await _prefs.getPrefs();
    // Filter at the client because Supabase's REST API doesn't support
    // "WHERE type IN (...)" with a dynamic list of enum literals
    // easily. We get all unread and filter here — the badge count is
    // small so this is fine.
    return response
        .where((m) => prefs[m['type'] as String] ?? true)
        .length;
  }
}
