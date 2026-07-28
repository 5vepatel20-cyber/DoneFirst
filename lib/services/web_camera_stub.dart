import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Non-web fallback. Never invoked (the caller guards on kIsWeb), but
/// it has to exist so the conditional import in web_camera.dart type-
/// checks on mobile/desktop where dart:ui_web isn't available.
Future<XFile?> openWebCamera(BuildContext context) async => null;
