import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProofImageViewer extends StatelessWidget {
  final String imageUrl;
  final String taskDescription;
  final Map<String, dynamic>? aiResult;

  const ProofImageViewer({
    super.key,
    required this.imageUrl,
    required this.taskDescription,
    this.aiResult,
  });

  @override
  Widget build(BuildContext context) {
    final decision = aiResult?['decision'] ?? 'pending';
    final parentDecision = aiResult?['parent_decision'] ?? 'pending';
    final confidence = aiResult?['confidence'] ?? 0.0;
    final reason = aiResult?['reason'] ?? '';
    final parentNote = aiResult?['parent_note'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(taskDescription)),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
          ),
          if (aiResult != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: decision == 'approved'
                  ? AppColors.success.withOpacity(0.08)
                  : decision == 'rejected'
                  ? AppColors.danger.withOpacity(0.08)
                  : AppColors.accent.withOpacity(0.08),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI: $decision',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: decision == 'approved'
                          ? AppColors.success
                          : decision == 'rejected'
                          ? AppColors.danger
                          : AppColors.accent,
                    ),
                  ),
                  Text(
                    'Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  if (reason.isNotEmpty) const SizedBox(height: 4),
                  if (reason.isNotEmpty)
                    Text(
                      reason,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  if (parentDecision != 'pending') ...[
                    const SizedBox(height: 8),
                    Divider(
                      height: 1,
                      color: AppColors.border.withOpacity(0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Parent: $parentDecision',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: parentDecision == 'approved'
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                    ),
                  ],
                  if (parentNote.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.comment,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            parentNote,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
