import 'package:flutter_screentime/flutter_screentime.dart';

class BlockingService {
  final _screenTime = FlutterScreentime();
  bool _isBlocking = false;
  bool _hasPermission = false;

  bool get isBlocking => _isBlocking;

  Future<bool> requestPermission() async {
    try {
      await _screenTime.requestAuthorization();
      _hasPermission = true;
      return true;
    } catch (e) {
      _hasPermission = false;
      return false;
    }
  }

  Future<void> showAppPicker() async {
    await _screenTime.selectBlockedApps();
  }

  Future<void> startBlocking() async {
    _isBlocking = true;
    if (_hasPermission) {
      try {
        await _screenTime.startBlocking();
      } catch (_) {}
    }
  }

  Future<void> stopBlocking() async {
    _isBlocking = false;
    if (_hasPermission) {
      try {
        await _screenTime.stopBlocking();
      } catch (_) {}
    }
  }
}
