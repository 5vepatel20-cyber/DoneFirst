import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

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
      final result = await InternetAddress.lookup('supabase.co')
          .timeout(const Duration(seconds: 5));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
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
