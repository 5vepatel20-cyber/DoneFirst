import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/proof_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../services/web_camera.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';

class ProofCaptureScreen extends StatefulWidget {
  final String taskId;
  final String taskDescription;
  final String taskSubject;
  const ProofCaptureScreen({
    super.key,
    required this.taskId,
    required this.taskDescription,
    this.taskSubject = 'General',
  });

  @override
  State<ProofCaptureScreen> createState() => _ProofCaptureScreenState();
}

class _ProofCaptureScreenState extends State<ProofCaptureScreen> {
  final _proofService = ProofService();
  final _notificationService = NotificationService();
  final _picker = ImagePicker();
  final _noteController = TextEditingController();
  final List<XFile> _images = [];
  bool _submitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    // On web, image_picker's ImageSource.camera can't open a live
    // camera — on desktop browsers it degrades to a plain file dialog
    // (the `capture` attribute is only honoured on mobile browsers).
    // Use our own getUserMedia-based capture so the snap-proof flow is
    // testable on desktop web. Native builds keep the platform camera.
    if (kIsWeb) {
      try {
        final shot = await captureFromWebCamera(context);
        if (shot != null && mounted) setState(() => _images.add(shot));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn’t open camera: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1920,
      );
      if (picked != null) setState(() => _images.add(picked));
    } catch (e) {
      // Camera permission denied, no camera on the device, or the
      // picker plugin threw on a misconfigured build. The older
      // code had no catch so the kid would tap "Take Photo" and
      // see nothing happen. Surface the real reason so they know
      // whether to retry or use the gallery instead.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t open camera: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _pickGallery() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1920,
      );
      if (picked != null) setState(() => _images.add(picked));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t open gallery: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (_images.isEmpty) return;
    setState(() => _submitting = true);
    try {
      // Uploads run in parallel — a 3-photo proof no longer takes
      // 3× the per-image time on a slow connection. The signed-URL
      // create is also inside the service call so we get them all
      // back at the same instant rather than serially.
      //
      // 60s per-image timeout is generous enough to survive a 3G
      // uplink without making a stuck upload look intentional.
      // A failure on any one image aborts the whole batch via
      // Future.wait's "first failure short-circuits" semantics —
      // partial successes aren't useful here (the proof row needs
      // a complete image_urls array), and we'd rather the parent
      // see the error and retry from scratch than have a half-
      // submitted proof that locks up the parent UI.
      final urls = await Future.wait(
        _images.map(
          (img) => _proofService
              .uploadImage(img, widget.taskId)
              .timeout(const Duration(seconds: 60)),
        ),
      );
      final sessionId = await _proofService.submitProofWithUrls(
        taskId: widget.taskId,
        imageUrls: urls,
        taskDescription: widget.taskDescription,
        subject: widget.taskSubject,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      final sessionData = await SessionService().getSessionById(sessionId);
      if (sessionData != null) {
        await _notificationService.insertNotification(
          parentId: sessionData.parentId,
          childId: sessionData.childId,
          type: 'proof_submitted',
          title:
              'Proof submitted (${urls.length} photo${urls.length > 1 ? 's' : ''})',
          body: widget.taskDescription,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Dark camera-screen palette (this screen IS the dark one).
  static const Color _ink = Color(0xFF17140F);
  static const Color _inkPanel = Color(0xFF221E17);
  static const Color _line = Color(0xFF3A3227);
  static const Color _dim = Color(0xFFB3AA9B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ink,
      body: SafeArea(
        child: _images.isEmpty ? _buildCameraView() : _buildReviewView(),
      ),
    );
  }

  /// Pre-capture: task name up top, framing brackets in the middle,
  /// hint text, and a big shutter at the bottom.
  Widget _buildCameraView() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Center(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: _FramingGuide(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.scanLine, size: 40, color: _dim),
                      const SizedBox(height: 14),
                      Text(
                        '[ point at your finished work ]',
                        textAlign: TextAlign.center,
                        style: AppText.label(color: _dim, size: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Shutter block.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Text(
                'Snap your finished work',
                style: AppText.cardHeader(color: Colors.white, size: 18),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Gallery fallback on the left.
                  _CircleAction(
                    icon: LucideIcons.image,
                    onTap: _pickGallery,
                    size: 48,
                    bg: _inkPanel,
                    border: _line,
                  ),
                  const SizedBox(width: 36),
                  // Big shutter.
                  GestureDetector(
                    onTap: _pickImage,
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
                          child: const Icon(
                            LucideIcons.camera,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 36),
                  const SizedBox(width: 48), // balance the row
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Post-capture: thumbnails, optional note, retake + submit.
  Widget _buildReviewView() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _images.length + 1,
            itemBuilder: (ctx, i) {
              if (i == _images.length) {
                return GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _inkPanel,
                      border: Border.all(color: _line),
                      borderRadius: BorderRadius.circular(AppRadius.tile),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.plus, color: AppColors.greenBright),
                        SizedBox(height: 4),
                        Text(
                          'Add more',
                          style: TextStyle(color: _dim, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                    child: kIsWeb
                        ? Image.network(
                            _images[i].path,
                            fit: BoxFit.cover,
                            height: double.infinity,
                            width: double.infinity,
                          )
                        : Image.file(
                            File(_images[i].path),
                            fit: BoxFit.cover,
                            height: double.infinity,
                            width: double.infinity,
                          ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _images.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.x,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              TextField(
                controller: _noteController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Note for a parent (optional)',
                  hintStyle: const TextStyle(color: _dim),
                  filled: true,
                  fillColor: _inkPanel,
                  prefixIcon: const Icon(
                    LucideIcons.messageSquare,
                    size: 18,
                    color: _dim,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    borderSide: const BorderSide(color: _line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    borderSide: const BorderSide(color: AppColors.greenBright),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _submitting ? null : () => setState(_images.clear),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _inkPanel,
                          borderRadius: BorderRadius.circular(AppRadius.button),
                          border: Border.all(color: _line),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              LucideIcons.rotateCcw,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Retake',
                              style: AppText.button(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: DfButton(
                      _submitting
                          ? 'Uploading…'
                          : 'Submit ${_images.length} photo${_images.length > 1 ? 's' : ''}',
                      icon: LucideIcons.uploadCloud,
                      loading: _submitting,
                      onPressed: _submitting ? null : _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.x, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SNAP PROOF', style: AppText.eyebrow(color: _dim)),
                const SizedBox(height: 2),
                Text(
                  widget.taskDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardHeader(color: Colors.white, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Corner-bracket framing guide on a dark camera surface.
class _FramingGuide extends StatelessWidget {
  final Widget child;
  const _FramingGuide({required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BracketPainter(),
      child: Center(child: child),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 30.0;
    const r = 14.0;
    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, len + r)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0)
        ..lineTo(len + r, 0),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - len - r, 0)
        ..lineTo(size.width - r, 0)
        ..quadraticBezierTo(size.width, 0, size.width, r)
        ..lineTo(size.width, len + r),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - len - r)
        ..lineTo(0, size.height - r)
        ..quadraticBezierTo(0, size.height, r, size.height)
        ..lineTo(len + r, size.height),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - len - r, size.height)
        ..lineTo(size.width - r, size.height)
        ..quadraticBezierTo(
          size.width,
          size.height,
          size.width,
          size.height - r,
        )
        ..lineTo(size.width, size.height - len - r),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small circular icon button used on the dark camera screen.
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color bg;
  final Color border;
  const _CircleAction({
    required this.icon,
    required this.onTap,
    required this.size,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: border),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
