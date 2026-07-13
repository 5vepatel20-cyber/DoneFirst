import 'package:flutter/material.dart';

import '../app_globals.dart' as app;

/// Thin wrapper around the global [ScaffoldMessengerState] so
/// callers without a [BuildContext] (realtime callbacks, edge-
/// function responses, periodic timers) can show SnackBars.
///
/// Backs onto [app.rootScaffoldMessengerKey]. The key must be
/// attached to MaterialApp.scaffoldMessengerKey in main.dart for
/// `show` to have anywhere to render — without it the calls are
/// silent no-ops (and we log nothing, because spamming console
/// would be worse than silently dropping a transient toast).
///
/// Default duration is 4s. Pair with [showFor] if you want a
/// "View" / "Undo" action button.
class ToastService {
  /// Shows a SnackBar with the given [message]. Optional [action]
  /// label + callback adds a tappable right-aligned button.
  /// Pass [backgroundColor] to override the default neutral fill
  /// (e.g. danger for a revoke notification).
  void show(
    String message, {
    String? action,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
    Color? backgroundColor,
  }) {
    final messenger = app.rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: backgroundColor,
        action: (action != null && onAction != null)
            ? SnackBarAction(
                label: action,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Convenience wrapper: shows a SnackBar for the requested
  /// duration but the user can dismiss it earlier via swipe.
  /// Provided so callers don't accidentally pass `duration: 0`.
  void showFor(
    String message, {
    Duration duration = const Duration(seconds: 3),
    Color? backgroundColor,
    String? action,
    VoidCallback? onAction,
  }) {
    show(
      message,
      duration: duration,
      backgroundColor: backgroundColor,
      action: action,
      onAction: onAction,
    );
  }
}