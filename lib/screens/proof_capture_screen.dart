import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/proof_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';

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
          (img) => _proofService.uploadImage(img, widget.taskId).timeout(
                const Duration(seconds: 60),
              ),
        ),
      );
      await _proofService.submitProofWithUrls(
        taskId: widget.taskId,
        imageUrls: urls,
        taskDescription: widget.taskDescription,
        subject: widget.taskSubject,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      final taskData = await Supabase.instance.client
          .from('homework_tasks')
          .select('session_id')
          .eq('id', widget.taskId)
          .single();
      final sessionData = await SessionService().getSessionById(
        taskData['session_id'] as String,
      );
      await _notificationService.insertNotification(
        parentId: sessionData!.parentId,
        childId: sessionData.childId,
        type: 'proof_submitted',
        title:
            'Proof submitted (${urls.length} photo${urls.length > 1 ? 's' : ''})',
        body: widget.taskDescription,
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add proof', style: AppText.screenTitle()),
            const SizedBox(height: 2),
            Text(widget.taskDescription, style: AppText.bodySecondary()),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: _images.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha:0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.camera,
                              size: 48,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Take photos of your completed homework',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(LucideIcons.camera),
                            label: const Text('Take Photo'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _pickGallery,
                            icon: const Icon(LucideIcons.image, size: 16),
                            label: const Text('Choose from Gallery'),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                      itemCount: _images.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == _images.length) {
                          return GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha:0.3),
                                  style: BorderStyle.solid,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(LucideIcons.plus, color: AppColors.forest),
                                  SizedBox(height: 4),
                                  Text(
                                    'Add more',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
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
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _images.removeAt(i)),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: AppColors.danger,
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
            if (_images.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note for parent (optional)',
                    hintText: 'Tell your parent about this...',
                    prefixIcon: Icon(LucideIcons.messageSquare, size: 18),
                  ),
                  maxLines: 2,
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.uploadCloud, size: 18),
                  label: Text(
                    _submitting
                        ? 'Uploading...'
                        : 'Submit ${_images.length} Photo${_images.length > 1 ? 's' : ''}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
