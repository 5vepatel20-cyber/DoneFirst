import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class NotificationService {
  final _supabase = Supabase.instance.client;

  Future<void> insertNotification({
    required String parentId,
    String? childId,
    required String type,
    required String title,
    String? body,
  }) async {
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
    return response.map((m) => AppNotification.fromMap(m)).toList();
  }

  Future<List<AppNotification>> getUnreadNotifications() async {
    final response = await _supabase
        .from('notifications')
        .select()
        .eq('parent_id', _supabase.auth.currentUser!.id)
        .eq('read', false)
        .order('created_at', ascending: false);
    return response.map((m) => AppNotification.fromMap(m)).toList();
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
        .select('id')
        .eq('parent_id', _supabase.auth.currentUser!.id)
        .eq('read', false);
    return response.length;
  }
}
