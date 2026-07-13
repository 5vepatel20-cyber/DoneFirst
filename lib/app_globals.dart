/// Top-level service singletons. Kept here so leaf widgets and
/// tests can import them without pulling the entire `main.dart`
/// (which transitively imports every screen, including the kid-app
/// screens that depend on services only present in the standalone
/// kid-app project).
///
/// `main.dart` re-uses these same instances and wires them into
/// the app; tests can construct fresh ones in setUp if they need
/// to isolate state.
library;

import 'package:flutter/material.dart';

import 'services/realtime_service.dart';
import 'services/toast_service.dart';

final realtimeService = RealtimeService();
final toastService = ToastService();

/// Global messenger key. Any code that holds a reference to
/// `app.toastService` can show a SnackBar from a non-context
/// path (realtime callbacks, edge-function responses, etc).
/// Wired up in [DoneFirstApp.build] via
/// [MaterialApp.scaffoldMessengerKey].
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();