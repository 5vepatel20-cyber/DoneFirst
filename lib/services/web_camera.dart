import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart' show XFile;

// Real implementation only exists on web (it needs getUserMedia and
// dart:ui_web). Everywhere else this resolves to the stub, which is
// never actually called — proof_capture_screen only routes here when
// kIsWeb is true — but the conditional import keeps the native build
// from ever seeing web-only libraries.
import 'web_camera_stub.dart'
    if (dart.library.js_interop) 'web_camera_web.dart';

/// Opens a full-screen live-camera capture UI (web only) and returns
/// the captured photo as an [XFile], or null if the user cancelled or
/// no camera was available. On non-web platforms this returns null and
/// callers should use the platform camera via image_picker instead.
Future<XFile?> captureFromWebCamera(BuildContext context) =>
    openWebCamera(context);
