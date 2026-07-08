import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

class ProofImageViewer extends StatefulWidget {
  final String imageUrl;
  final String taskDescription;
  final ProofSubmission? aiResult;

  const ProofImageViewer({
    super.key,
    required this.imageUrl,
    required this.taskDescription,
    this.aiResult,
  });

  @override
  State<ProofImageViewer> createState() => _ProofImageViewerState();
}

class _ProofImageViewerState extends State<ProofImageViewer> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<String> get _allUrls {
    final urls = <String>[];
    if (widget.imageUrl.isNotEmpty) urls.add(widget.imageUrl);
    if (widget.aiResult != null) {
      for (final u in widget.aiResult!.imageUrls) {
        if (!urls.contains(u)) urls.add(u);
      }
    }
    return urls;
  }

  @override
  Widget build(BuildContext context) {
    final decision = widget.aiResult?.aiDecision ?? 'pending';
    final parentDecision = widget.aiResult?.parentDecision ?? 'pending';
    final confidence = widget.aiResult?.aiConfidence ?? 0.0;
    final reason = widget.aiResult?.aiReason ?? '';
    final parentNote = widget.aiResult?.parentNote ?? '';
    final allUrls = _allUrls;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.taskDescription),
        actions: allUrls.length > 1
            ? [
                Center(
                  child: Text(
                    '${_currentPage + 1}/${allUrls.length}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: allUrls.length > 1
                ? PageView(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    children: allUrls
                        .map(
                          (url) => InteractiveViewer(
                            child: Image.network(url, fit: BoxFit.contain),
                          ),
                        )
                        .toList(),
                  )
                : InteractiveViewer(
                    child: Image.network(widget.imageUrl, fit: BoxFit.contain),
                  ),
          ),
          if (allUrls.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(allUrls.length, (i) {
                  return Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _currentPage
                          ? AppColors.primary
                          : AppColors.border,
                    ),
                  );
                }),
              ),
            ),
          if (widget.aiResult != null)
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
