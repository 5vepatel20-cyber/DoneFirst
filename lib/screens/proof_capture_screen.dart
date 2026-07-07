import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/proof_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class ProofCaptureScreen extends StatefulWidget {
  final String taskId;
  final String taskDescription;
  const ProofCaptureScreen({
    super.key,
    required this.taskId,
    required this.taskDescription,
  });

  @override
  State<ProofCaptureScreen> createState() => _ProofCaptureScreenState();
}

class _ProofCaptureScreenState extends State<ProofCaptureScreen> {
  final _proofService = ProofService();
  final _notificationService = NotificationService();
  final _picker = ImagePicker();
  final _noteController = TextEditingController();
  final List<File> _images = [];
  bool _submitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked != null) setState(() => _images.add(File(picked.path)));
  }

  Future<void> _pickGallery() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _images.add(File(picked.path)));
  }

  Future<void> _submit() async {
    if (_images.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final urls = <String>[];
      for (final img in _images) {
        final url = await _proofService.uploadImage(img, widget.taskId);
        urls.add(url);
      }
      await _proofService.submitProofWithUrls(
        taskId: widget.taskId,
        imageUrls: urls,
        taskDescription: widget.taskDescription,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      final taskData = await Supabase.instance.client
          .from('homework_tasks')
          .select('session_id')
          .eq('id', widget.taskId)
          .single();
      final sessionData = await Supabase.instance.client
          .from('homework_sessions')
          .select('parent_id, child_id')
          .eq('id', taskData['session_id'])
          .single();
      await _notificationService.insertNotification(
        parentId: sessionData['parent_id'] as String,
        childId: sessionData['child_id'] as String?,
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
      appBar: AppBar(title: Text('Proof: ${widget.taskDescription}')),
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
                              color: AppColors.primary.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
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
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Take Photo'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _pickGallery,
                            icon: const Icon(Icons.photo_library),
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
                                  color: AppColors.primary.withOpacity(0.3),
                                  style: BorderStyle.solid,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add, color: AppColors.primary),
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
                              child: Image.file(
                                _images[i],
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
                                    Icons.close,
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
                    prefixIcon: Icon(Icons.comment, size: 20),
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
                      : const Icon(Icons.cloud_upload),
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
