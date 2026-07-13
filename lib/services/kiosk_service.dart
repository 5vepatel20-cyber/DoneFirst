import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-side wrapper for the native `donefirst/kiosk` MethodChannel
/// registered in MainActivity.kt.
///
/// Two complementary enforcement layers run when a lock starts:
///   1. [BlockingService] (flutter_screentime) blocks individual
///      apps via AccessibilityService + UsageStatsManager.
///   2. [KioskService] (this) calls Activity.startLockTask() to
///      engage OS-level kiosk mode — home/back/recent-app buttons
///      are intercepted system-wide and the launcher is hidden.
///
/// Layer 2 only works when our package is the device owner (set
/// via ADB at install time — see SETUP.md). When we are NOT the
/// device owner, startLockTask silently returns false and the
/// service still reports isEnabled=true (the API is "available");
/// the caller is responsible for not promising kiosk enforcement
/// on devices that haven't been promoted.
class KioskService {
  static const MethodChannel _channel = MethodChannel('donefirst/kiosk');

  bool _isDeviceOwner = false;
  bool _isLocked = false;

  /// True if the native side reports our app is the device owner.
  /// Computed once at app start by [KioskService.refreshDeviceOwner].
  bool get isDeviceOwner => _isDeviceOwner;

  /// True if startLockTask() has been called and stopLockTask()
  /// has not yet followed. May be true even when [isDeviceOwner]
  /// is false (the OS silently no-ops the call).
  bool get isLocked => _isLocked;

  /// Ask the native side whether we're the device owner. Cached
  /// for the lifetime of the app — device-owner status can't
  /// change at runtime without an ADB command, so a single
  /// refresh on boot is enough.
  Future<void> refreshDeviceOwner() async {
    try {
      final result = await _channel.invokeMethod<bool>('isDeviceOwner');
      _isDeviceOwner = result ?? false;
    } on MissingPluginException {
      // Running in a Flutter test or on a non-Android platform
      // (e.g. iOS sim for dev). Treat as not-device-owner so the
      // app behaves like a no-op lock.
      _isDeviceOwner = false;
    } on PlatformException catch (e) {
      debugPrint('refreshDeviceOwner PlatformException: ${e.message}');
      _isDeviceOwner = false;
    }
  }

  /// Engage OS-level lock-task mode. Returns true if the OS
  /// honoured the call. Returns false silently if we are not the
  /// device owner (the caller should rely on BlockingService
  /// alone in that case).
  Future<bool> startLockTask() async {
    try {
      final ok = await _channel.invokeMethod<bool>('startLockTask');
      _isLocked = ok ?? false;
      return _isLocked;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('startLockTask PlatformException: ${e.message}');
      _isLocked = false;
      return false;
    }
  }

  /// Release OS-level lock-task mode. No-op if we are not in
  /// lock-task mode, or not the device owner.
  Future<void> stopLockTask() async {
    try {
      await _channel.invokeMethod<void>('stopLockTask');
      _isLocked = false;
    } on MissingPluginException {
      // test/non-Android path
    } on PlatformException catch (e) {
      debugPrint('stopLockTask PlatformException: ${e.message}');
    }
  }
}
