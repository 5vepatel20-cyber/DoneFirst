import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getNotifications() async {
    final response = await _supabase
        .from('notifications')
        .select()
        .eq('parent_id', _supabase.auth.currentUser!.id)
        .order('created_at', ascending: false)
        .limit(50);
    return response;
  }

  Future<int> getUnreadCount() async {
    final response = await _supabase
        .from('notifications')
        .select('id')
        .eq('parent_id', _supabase.auth.currentUser!.id)
        .eq('read', false);
    return response.length;
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
    });
  }
}
