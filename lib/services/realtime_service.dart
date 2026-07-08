import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _notificationsChannel;
  RealtimeChannel? _proofsChannel;
  RealtimeChannel? _breaksChannel;
  bool _listening = false;
  int _unreadCount = 0;

  bool get listening => _listening;
  int get unreadCount => _unreadCount;

  VoidCallback? onNewNotification;
  VoidCallback? onNewProof;
  VoidCallback? onNewBreakRequest;

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
  }

  void setUnreadCount(int count) {
    _unreadCount = count;
    notifyListeners();
  }

  void stopListening() {
    _notificationsChannel?.unsubscribe();
    _proofsChannel?.unsubscribe();
    _breaksChannel?.unsubscribe();
    _listening = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
