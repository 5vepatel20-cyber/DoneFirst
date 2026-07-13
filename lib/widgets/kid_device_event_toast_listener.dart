import 'package:flutter/material.dart';

import '../app_globals.dart' as app;
import '../services/kid_device_service.dart';
import '../theme/app_theme.dart';

/// Listens for kid_device_events INSERTs and shows transient
/// SnackBars for the events a parent cares about:
///   • device_revoked → red toast (security-relevant) with child +
///     device names pulled from the realtime payload
///   • code_claimed → green toast (their kid paired successfully)
///   • code_generated / code_cancelled → suppressed; these are
///     the parent's own actions and would be noisy self-toasts.
///
/// Wraps the parent dashboard body (or any subtree that wants the
/// live toasts). Idempotent: the save-previous / restore-on-dispose
/// pattern means a second instance chains, not clobbers.
class KidDeviceEventToastListener extends StatefulWidget {
  final Widget child;

  const KidDeviceEventToastListener({super.key, required this.child});

  @override
  State<KidDeviceEventToastListener> createState() =>
      _KidDeviceEventToastListenerState();
}

class _KidDeviceEventToastListenerState
    extends State<KidDeviceEventToastListener> {
  void Function(Map<String, dynamic>)? _previousHandler;

  @override
  void initState() {
    super.initState();
    _previousHandler = app.realtimeService.onNewKidDeviceEvent;
    app.realtimeService.onNewKidDeviceEvent = _onNewEvent;
  }

  @override
  void dispose() {
    // Restore whatever was registered before us so the activity
    // feed (or anything else downstream of us) keeps getting
    // callbacks.
    app.realtimeService.onNewKidDeviceEvent = _previousHandler;
    super.dispose();
  }

  void _onNewEvent(Map<String, dynamic> newRow) {
    // Chain to whatever was registered before us (the activity
    // feed, etc.) so handlers don't starve each other.
    _previousHandler?.call(newRow);

    final type = newRow['event_type'] as String?;
    if (type == null) return;

    // The view that backs the activity feed joins in child_name +
    // device_name. Realtime payloads are the raw INSERT row, so
    // those fields are usually null on this code path. Fall back
    // to generic copy when they're absent rather than showing
    // "<unknown child>'s <unknown device>".
    final childName = newRow['child_name'] as String?;
    final deviceName = newRow['device_name'] as String?;

    switch (type) {
      case KidDeviceEvent.typeDeviceRevoked:
        // Revoke is the only red toast — it's the parent's most
        // important notification and easy to miss in a long feed.
        final msg = (childName != null && deviceName != null)
            ? '$deviceName for $childName was revoked'
            : 'A kid device was revoked';
        app.toastService.show(
          msg,
          duration: const Duration(seconds: 5),
          backgroundColor: AppColors.danger,
          action: 'View',
          onAction: () => _navigateToSettings(),
        );
        break;
      case KidDeviceEvent.typeCodeClaimed:
        final msg = (childName != null && deviceName != null)
            ? '$childName paired $deviceName'
            : 'A kid device paired successfully';
        app.toastService.show(
          msg,
          duration: const Duration(seconds: 3),
          backgroundColor: AppColors.grass,
        );
        break;
      // code_generated / code_cancelled are parent-initiated —
      // skip the toast to avoid self-notification noise.
    }
  }

  void _navigateToSettings() {
    // The "View" action from a revoke toast should land on the
    // device list. We use rootNavigator so the snackbar overlay
    // (which sits above the route stack) can drive navigation
    // even if the user dismissed whatever screen they were on.
    final nav = app.rootScaffoldMessengerKey.currentContext;
    if (nav == null) return;
    Navigator.of(nav, rootNavigator: true).pushNamed('/settings');
    // Then the user can tap "Kid devices" from Settings. A more
    // direct route would push KidDevicePairingScreen directly,
    // but we don't import that screen here to keep this widget
    // dependency-light; routing through Settings is one tap more
    // but never breaks if the screen is renamed.
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
