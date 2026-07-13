import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _notificationsChannel;
  RealtimeChannel? _proofsChannel;
  RealtimeChannel? _breaksChannel;
  RealtimeChannel? _kidDeviceEventsChannel;
  RealtimeChannel? _kidDevicesChannel;
  bool _listening = false;
  int _unreadCount = 0;

  bool get listening => _listening;
  int get unreadCount => _unreadCount;

  VoidCallback? onNewNotification;
  VoidCallback? onNewProof;
  VoidCallback? onNewBreakRequest;
  /// Fires when a new row lands in kid_device_events. Payload
  /// is the new row's columns (NOT the joined view — consumers
  /// should re-fetch via KidDeviceEventService.listFamilyEvents
  /// if they need the child/device display names).
  void Function(Map<String, dynamic> newRow)? onNewKidDeviceEvent;
  /// Fires when a kid_devices row updates (heartbeat = last_seen_at
  /// bump, OR parent revoke = revoked_at). Payload is the new
  /// row. Consumer should re-fetch via KidDeviceService if it
  /// needs the joined status (e.g. online/recent/stale).
  void Function(Map<String, dynamic> newRow)? onKidDeviceChanged;

  void startListening() {
    if (_listening) return;
    _listening = true;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _notificationsChannel = _supabase
        .channel('notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            final newCount = _unreadCount + 1;
            _unreadCount = newCount;
            notifyListeners();
            onNewNotification?.call();
          },
        )
        .subscribe();

    _proofsChannel = _supabase
        .channel('proofs')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'proof_submissions',
          callback: (_) {
            notifyListeners();
            onNewProof?.call();
          },
        )
        .subscribe();

    _breaksChannel = _supabase
        .channel('breaks')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'break_requests',
          callback: (_) {
            notifyListeners();
            onNewBreakRequest?.call();
          },
        )
        .subscribe();

    // kid_device_events INSERT — emitted by the Postgres triggers
    // in migration_14. RLS keeps each parent scoped to their
    // family's events, but realtime doesn't auto-filter, so the
    // consumer must check the family_id before prepending.
    _kidDeviceEventsChannel = _supabase
        .channel('kid_device_events')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'kid_device_events',
          callback: (payload) {
            notifyListeners();
            final newRow = payload.newRecord;
            if (newRow.isNotEmpty) {
              onNewKidDeviceEvent?.call(newRow);
            }
          },
        )
        .subscribe();

    // kid_devices UPDATE — fires on every heartbeat (last_seen_at
    // bump) and on parent revokes (revoked_at set). Both are
    // useful to reflect immediately: heartbeat flips the dot
    // green within ms instead of waiting for the next 10s poll;
    // revoke propagates to co-parents instantly.
    _kidDevicesChannel = _supabase
        .channel('kid_devices')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'kid_devices',
          callback: (payload) {
            notifyListeners();
            final newRow = payload.newRecord;
            if (newRow.isNotEmpty) {
              onKidDeviceChanged?.call(newRow);
            }
          },
        )
        .subscribe();
  }

  void setUnreadCount(int count) {
    _unreadCount = count;
    notifyListeners();
  }

  void stopListening() {
    _notificationsChannel?.unsubscribe();
    _proofsChannel?.unsubscribe();
    _breaksChannel?.unsubscribe();
    _kidDeviceEventsChannel?.unsubscribe();
    _kidDevicesChannel?.unsubscribe();
    _listening = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
