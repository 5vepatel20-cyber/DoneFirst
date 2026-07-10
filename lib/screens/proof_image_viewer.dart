import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/proof_thumbnail.dart';

/// Proof photos are stored in a private Supabase bucket and served
/// via 7-day signed URLs (see uploadImageToStorage in ProofService).
/// We surface that to the parent here so the constraint isn't
/// invisible — the data-export notes already warn about it, but
/// those notes are only seen when a parent goes to download their
/// data. Most parents will never read that.
const Duration _signedUrlLifetime = Duration(days: 7);
const Duration _expiryWarnWindow = Duration(days: 2);

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

  /// Three states for the URL-expiry warning:
  /// - still has plenty of life: return null (no warning)
  /// - within 2 days of expiry: return a warn-style message
  /// - already past expiry: return a danger-style message
  ///
  /// Computed from proof.createdAt + 7 days. We use 2 days as the
  /// warn window because the export-notes copy already mentions the
  /// 7-day limit, and we want the in-app warning to be the more
  /// urgent reminder.
  ({String text, Color color, IconData icon})? _expiryWarning() {
    final createdAt = widget.aiResult?.createdAt;
    if (createdAt == null) return null;
    final expiresAt = createdAt.add(_signedUrlLifetime);
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return (
        text: 'Photo URL expired',
        color: AppColors.danger,
        icon: Icons.error_outline,
      );
    }
    if (remaining <= _expiryWarnWindow) {
      final days = remaining.inDays;
      final hours = remaining.inHours;
      final text = days >= 1
          ? 'URL expires in $days day${days == 1 ? '' : 's'}'
          : 'URL expires in $hours hr';
      return (
        text: text,
        color: AppColors.warning,
        icon: Icons.schedule,
      );
    }
    return null;
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
        actions: [
          // URL-expiry warning. Lives in the AppBar so it's always
          // visible while the parent is looking at the photo, without
          // overlapping the AI/parent footer below. Tapping it shows
          // a tooltip with the same text for a11y / long-text cases.
          if (_expiryWarning() != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Tooltip(
                  message: _expiryWarning()!.text,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _expiryWarning()!.icon,
                        color: _expiryWarning()!.color,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _expiryWarning()!.text,
                        style: TextStyle(
                          color: _expiryWarning()!.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (allUrls.length > 1)
            Center(
              child: Text(
                '${_currentPage + 1}/${allUrls.length}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
        ],
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
                            child: ProofThumbnail(
                              url: url,
                              fit: BoxFit.contain,
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                        )
                        .toList(),
                  )
                : InteractiveViewer(
                    child: ProofThumbnail(
                      url: widget.imageUrl,
                      fit: BoxFit.contain,
                      borderRadius: BorderRadius.zero,
                    ),
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
                  ? AppColors.success.withValues(alpha:0.08)
                  : decision == 'rejected'
                  ? AppColors.danger.withValues(alpha:0.08)
                  : AppColors.accent.withValues(alpha:0.08),
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
                      color: AppColors.border.withValues(alpha:0.3),
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
