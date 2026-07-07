import 'package:flutter_screentime/flutter_screentime.dart';

class BlockingService {
  final _screenTime = FlutterScreentime();

  Future<bool> requestPermission() async {
    try {
      await _screenTime.requestAuthorization();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> showAppPicker() async {
    await _screenTime.selectBlockedApps();
  }

  Future<void> startBlocking() async {
    await _screenTime.startBlocking();
  }

  Future<void> stopBlocking() async {
    await _screenTime.stopBlocking();
  }
}
