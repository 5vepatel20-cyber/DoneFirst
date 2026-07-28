import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:web/web.dart' as web;

import '../theme/app_theme.dart';

/// Monotonic id so every capture registers a fresh platform-view type.
/// Reusing a viewType across opens can hand HtmlElementView a stale
/// (already-disposed) <video>, so we never recycle one.
int _viewSeq = 0;

/// Opens a full-screen live-camera page backed by the browser's
/// getUserMedia. Pops with the captured [XFile], or null on cancel /
/// permission-denied / no-camera. Only compiled into the web build.
Future<XFile?> openWebCamera(BuildContext context) {
  return Navigator.of(context).push<XFile>(
    MaterialPageRoute<XFile>(
      fullscreenDialog: true,
      builder: (_) => const _WebCameraPage(),
    ),
  );
}

class _WebCameraPage extends StatefulWidget {
  const _WebCameraPage();

  @override
  State<_WebCameraPage> createState() => _WebCameraPageState();
}

class _WebCameraPageState extends State<_WebCameraPage> {
  // Dark palette matched to ProofCaptureScreen so the capture flow
  // feels like one screen, not two.
  static const Color _ink = Color(0xFF17140F);
  static const Color _dim = Color(0xFFB3AA9B);

  web.MediaStream? _stream;
  web.HTMLVideoElement? _video;
  String? _viewType;
  String? _error;
  bool _ready = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final stream = await _openStream();
      final video = web.HTMLVideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true')
        ..srcObject = stream;
      video.style
        ..width = '100%'
        ..height = '100%'
        ..objectFit = 'cover';
      // play() can reject if autoplay is blocked; muted+user-gesture
      // (the shutter tap that got us here) makes that unlikely, and a
      // rejection here shouldn't tear down the whole page.
      video.play().toDart.catchError((Object _) => null);

      final viewType = 'web-camera-${_viewSeq++}';
      ui_web.platformViewRegistry
          .registerViewFactory(viewType, (int _) => video);

      if (!mounted) {
        _stopStream(stream);
        return;
      }
      setState(() {
        _stream = stream;
        _video = video;
        _viewType = viewType;
        _ready = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanError(e));
    }
  }

  /// Prefer the rear camera on phones; fall back to any camera on a
  /// desktop that has no "environment" facing device.
  Future<web.MediaStream> _openStream() async {
    final md = web.window.navigator.mediaDevices;
    try {
      return await md
          .getUserMedia(
            web.MediaStreamConstraints(
              video: web.MediaTrackConstraints(facingMode: 'environment'.toJS),
              audio: false.toJS,
            ),
          )
          .toDart;
    } catch (_) {
      return await md
          .getUserMedia(web.MediaStreamConstraints(video: true.toJS))
          .toDart;
    }
  }

  String _humanError(Object e) {
    final s = e.toString();
    if (s.contains('NotAllowedError') || s.contains('Permission')) {
      return 'Camera access was blocked. Allow the camera in your '
          'browser and try again.';
    }
    if (s.contains('NotFoundError') || s.contains('DevicesNotFound')) {
      return 'No camera was found on this device.';
    }
    return 'Couldn’t open the camera: $s';
  }

  Future<void> _capture() async {
    final video = _video;
    if (video == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final w = video.videoWidth;
      final h = video.videoHeight;
      final canvas = web.HTMLCanvasElement()
        ..width = w
        ..height = h;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      ctx.drawImage(video as web.CanvasImageSource, 0, 0);
      final dataUrl = canvas.toDataURL('image/jpeg', 0.85.toJS);
      final bytes = base64.decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
      final shot = XFile.fromData(
        bytes,
        mimeType: 'image/jpeg',
        name: 'proof_$_viewSeq.jpg',
      );
      if (mounted) Navigator.of(context).pop(shot);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = 'Couldn’t capture the photo: $e';
      });
    }
  }

  void _stopStream(web.MediaStream stream) {
    final tracks = stream.getTracks().toDart;
    for (final t in tracks) {
      t.stop();
    }
  }

  @override
  void dispose() {
    final stream = _stream;
    if (stream != null) _stopStream(stream);
    _video?.srcObject = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ink,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _preview()),
            // Close button.
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // Shutter.
            if (_ready && _error == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Center(child: _shutter()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.cameraOff, color: _dim, size: 40),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppText.body(color: Colors.white),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Close',
                  style: AppText.button(color: AppColors.greenBright),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready || _viewType == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return HtmlElementView(viewType: _viewType!);
  }

  Widget _shutter() {
    return GestureDetector(
      onTap: _capturing ? null : _capture,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 4),
        ),
        child: Center(
          child: Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.green,
            ),
            child: _capturing
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : const Icon(LucideIcons.camera, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
