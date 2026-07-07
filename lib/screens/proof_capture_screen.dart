import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/proof_service.dart';
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
  final _picker = ImagePicker();
  File? _image;
  bool _submitting = false;
  Map<String, dynamic>? _result;

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked != null) setState(() => _image = File(picked.path));
  }

  Future<void> _pickGallery() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _image = File(picked.path));
  }

  Future<void> _submit() async {
    if (_image == null) return;
    setState(() => _submitting = true);
    try {
      final result = await _proofService.submitProof(
        taskId: widget.taskId,
        image: _image!,
        taskDescription: widget.taskDescription,
      );
      setState(() => _result = result);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _submitting = false);
    }
    if (mounted) Navigator.pop(context);
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
              child: _image == null
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
                            'Take a photo of your completed homework',
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
                  : Column(
                      children: [
                        Expanded(
                          child: Image.file(_image!, fit: BoxFit.contain),
                        ),
                        const SizedBox(height: 16),
                        if (_result != null && _result!['ai'] != null)
                          Card(
                            color: _result!['ai']['decision'] == 'approved'
                                ? AppColors.success.withOpacity(0.1)
                                : _result!['ai']['decision'] == 'rejected'
                                ? AppColors.danger.withOpacity(0.1)
                                : AppColors.accent.withOpacity(0.1),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(
                                    'AI: ${_result!['ai']['decision']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Confidence: ${(_result!['ai']['confidence'] * 100).toStringAsFixed(0)}%',
                                  ),
                                  Text('${_result!['ai']['reason']}'),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            if (_image != null && _result == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit Proof'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
