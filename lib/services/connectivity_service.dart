import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ConnectivityService extends ChangeNotifier {
  bool _isOnline = true;
  Timer? _checkTimer;

  bool get isOnline => _isOnline;

  ConnectivityService() {
    _startMonitoring();
  }

  void _startMonitoring() {
    _checkNow();
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkNow());
  }

  Future<void> _checkNow() async {
    try {
      final response = await http.get(
        Uri.parse('https://wxjtksxugsirpowptpmz.supabase.co/rest/v1/'),
      ).timeout(const Duration(seconds: 5));
      final online = response.statusCode < 500;
      if (online != _isOnline) {
        _isOnline = online;
        notifyListeners();
      }
    } catch (_) {
      if (_isOnline) {
        _isOnline = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }
}
