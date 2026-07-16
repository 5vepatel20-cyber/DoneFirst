import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screentime/flutter_screentime.dart';

import 'kid_device_service.dart' show KidDevice;

/// Identifier for a single Android permission the parent app needs
/// before it can start blocking. Each maps to one row on
/// [DevicePermissionsScreen] and to one branch of the
/// `donefirst/permissions` MethodChannel.
///
/// The set is intentionally the same pair that flutter_screentime's
/// `currentAuthorizationStatus()` checks on Android — Usage Access
/// + Display Over Other Apps. We expose them individually so the
/// UI can drive a per-row "Grant" button and re-render only the
/// row whose underlying permission state actually changed.
enum BlockingPermission {
  /// AppOpsManager.OPSTR_GET_USAGE_STATS — lets the plugin see
  /// which apps are foregrounded so it can decide when to invoke
  /// the block screen.
  usageAccess('usage_access', 'Usage access'),

  /// Settings.ACTION_MANAGE_OVERLAY_PERMISSION — lets the block
  /// screen render on top of any foreground app.
  overlay('overlay', 'Display over other apps');

  const BlockingPermission(this.id, this.label);

  /// Stable identifier used in the MethodChannel call. Lowercase
  /// snake_case to match the convention in platform-channel args.
  final String id;

  /// Human-readable label rendered in the UI.
  final String label;
}

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
  /// Per-permission check + grant channel, registered in
  /// MainActivity.kt. Kept separate from the flutter_screentime
  /// channel so that future forks / iOS-side implementations
  /// can opt-in without dragging in screentime's surface.
  static const MethodChannel _permissionsChannel =
      MethodChannel('donefirst/permissions');

  final _screenTime = FlutterScreentime();

  BlockingStatus _status = BlockingStatus.idle;
  String? _lastError;

  BlockingStatus get status => _status;
  String? get lastError => _lastError;
  bool get hasPermission => _status.hasPermission;
  bool get isBlocking => _status.isActive;
  bool get isError => _status.isError;

  /// Read the current OS-level grant state for every permission
  /// BlockingService cares about. Returns false for permissions
  /// that don't apply on the current platform (iOS, web, Flutter
  /// test) so the UI can render rows but show them as already
  /// satisfied — those surfaces have no equivalent toggle and
  /// the OS dialogs aren't applicable.
  Future<Map<BlockingPermission, bool>> currentPermissions() async {
    final result = <BlockingPermission, bool>{};
    for (final p in BlockingPermission.values) {
      try {
        final granted = await _permissionsChannel.invokeMethod<bool>(
          switch (p) {
            BlockingPermission.usageAccess => 'checkUsageAccess',
            BlockingPermission.overlay => 'checkOverlay',
          },
        );
        result[p] = granted ?? false;
      } on MissingPluginException {
        // Test / web / non-Android — treat as granted so the
        // device-permissions screen's Continue button is enabled
        // and we don't block the user on a platform where the
        // permission doesn't exist.
        result[p] = true;
      } on PlatformException catch (e) {
        debugPrint('check ${p.id} PlatformException: ${e.message}');
        result[p] = false;
      }
    }
    return result;
  }

  /// Open the OS settings screen where the user can toggle the
  /// named permission. Returns true if the intent was dispatched
  /// (the user still has to actually flip the toggle themselves).
  ///
  /// The DevicePermissionsScreen re-reads [currentPermissions]
  /// from a `WidgetsBindingObserver.didChangeAppLifecycleState`
  /// resume hook so the row flips to "✓ On" the moment the user
  /// returns to the app with the toggle granted.
  Future<bool> openPermissionSettings(BlockingPermission permission) async {
    try {
      final ok = await _permissionsChannel.invokeMethod<bool>(
        switch (permission) {
          BlockingPermission.usageAccess => 'openUsageAccessSettings',
          BlockingPermission.overlay => 'openOverlaySettings',
        },
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('open ${permission.id} PlatformException: ${e.message}');
      return false;
    }
  }

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

  /// Start blocking. Requests permission first if we don't have it.
  /// Returns true if blocking is now active. On failure, [lastError] is
  /// populated and [status] becomes [BlockingStatus.blockingFailed].
  Future<bool> startBlocking() async {
    if (!_status.hasPermission) {
      final granted = await requestPermission();
      if (!granted) return false;
    }
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

/// Should the parent app skip its own flutter_screentime call when
/// the lock state changes? Yes if a kid device is paired (and not
/// revoked) — enforcement rides on Supabase realtime to the kid app's
/// own flutter_screentime + kiosk lock-task, which is the correct
/// enforcement surface. Without this gate the parent app would try
/// to block apps on its own device, which is useless if the kid
/// has their own phone, and would surface a permission error if no
/// usage-stats grant is set on the parent device.
///
/// Falls through to local blocking only when there's no paired
/// device (single-device mode: parent + kid share one phone).
bool shouldSkipLocalBlockingOnKidDevice(KidDevice? device) =>
    device != null && !device.isRevoked;