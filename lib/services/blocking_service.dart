import 'package:flutter/foundation.dart';
import 'package:flutter_screentime/flutter_screentime.dart';

/// State of the native app-blocking integration.
///
/// Exposed via [BlockingService] (a [ChangeNotifier]) so UI can react to
/// permission denials, blocking failures, etc. Previously these were
/// silently swallowed — kids had no idea blocking didn't start.
enum BlockingStatus {
  /// No state yet. Default before [BlockingService.requestPermission].
  idle,

  /// Awaiting user response to the OS permission dialog.
  requestingPermission,

  /// User denied the OS-level permission (FamilyControls on iOS,
  /// UsageStats / Accessibility on Android). Blocking cannot start
  /// until they grant it via Settings.
  permissionDenied,

  /// Permission granted but no block session is currently active.
  permissionGranted,

  /// Native plugin is initializing the block.
  startingBlock,

  /// Apps are actively being blocked.
  blockingActive,

  /// [startBlocking] failed after permission was granted (e.g. the
  /// underlying plugin threw). UI should surface [BlockingService.lastError].
  blockingFailed,

  /// Native plugin is releasing the block.
  stoppingBlock,

  /// [stopBlocking] failed. Unusual but possible if the OS revokes the
  /// block from under us. UI should surface [BlockingService.lastError].
  blockingError,
}

extension BlockingStatusX on BlockingStatus {
  bool get hasPermission =>
      this == BlockingStatus.permissionGranted ||
      this == BlockingStatus.blockingActive;

  bool get isActive => this == BlockingStatus.blockingActive;

  bool get isError =>
      this == BlockingStatus.permissionDenied ||
      this == BlockingStatus.blockingFailed ||
      this == BlockingStatus.blockingError;
}

/// Wraps `flutter_screentime` so the rest of the app can react to the
/// underlying OS-level state instead of having `try/catch (_) {}`
/// silently swallow failures.
///
/// On web this is effectively a no-op (the plugin does nothing) but the
/// service still tracks its own state, which lets the UI render
/// consistent messages everywhere.
class BlockingService extends ChangeNotifier {
  final _screenTime = FlutterScreentime();

  BlockingStatus _status = BlockingStatus.idle;
  String? _lastError;

  BlockingStatus get status => _status;
  String? get lastError => _lastError;
  bool get hasPermission => _status.hasPermission;
  bool get isBlocking => _status.isActive;
  bool get isError => _status.isError;

  void _setStatus(BlockingStatus newStatus, [String? error]) {
    _status = newStatus;
    _lastError = error;
    notifyListeners();
  }

  /// Prompt the OS for the permission needed to block apps. Returns true
  /// if granted, false if denied or the call threw.
  Future<bool> requestPermission() async {
    _setStatus(BlockingStatus.requestingPermission);
    try {
      await _screenTime.requestAuthorization();
      _setStatus(BlockingStatus.permissionGranted);
      return true;
    } catch (e) {
      _setStatus(BlockingStatus.permissionDenied, e.toString());
      return false;
    }
  }

  /// Start blocking. Does NOT auto-request permission — the call site
  /// is the only place that should decide whether to ask the user.
  /// Returns true if blocking is now active. On failure, [lastError]
  /// is populated and [status] becomes [BlockingStatus.blockingFailed].
  ///
  /// Pre-launch this method implicitly prompted the user for the OS
  /// grant on first call, which surprised parents in the middle of
  /// starting a session. Now callers must invoke [requestPermission]
  /// explicitly if they want to gate on it. Native enforcement code
  /// (Android AccessibilityService / iOS FamilyControls) isn't shipped
  /// yet, so most calls effectively no-op anyway.
  Future<bool> startBlocking() async {
    _setStatus(BlockingStatus.startingBlock);
    try {
      await _screenTime.startBlocking();
      _setStatus(BlockingStatus.blockingActive);
      return true;
    } catch (e) {
      _setStatus(BlockingStatus.blockingFailed, e.toString());
      return false;
    }
  }

  /// Stop blocking. Returns true if the block was released. The status
  /// returns to [BlockingStatus.permissionGranted] on success (the user
  /// still has the OS-level grant, just not blocking right now).
  Future<bool> stopBlocking() async {
    _setStatus(BlockingStatus.stoppingBlock);
    try {
      await _screenTime.stopBlocking();
      _setStatus(BlockingStatus.permissionGranted);
      return true;
    } catch (e) {
      _setStatus(BlockingStatus.blockingError, e.toString());
      return false;
    }
  }

  /// Clear the last-error and re-arm the service to [BlockingStatus.idle].
  /// Call after the user has acknowledged an error in the UI.
  void acknowledgeError() {
    if (_status.isError) {
      _setStatus(BlockingStatus.idle);
    }
  }
}