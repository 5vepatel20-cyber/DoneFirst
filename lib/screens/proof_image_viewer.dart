import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/df_kit.dart';
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
        color: AppColors.dangerFg,
        icon: LucideIcons.alertCircle,
      );
    }
    if (remaining <= _expiryWarnWindow) {
      final days = remaining.inDays;
      final hours = remaining.inHours;
      final text = days >= 1
          ? 'URL expires in $days day${days == 1 ? '' : 's'}'
          : 'URL expires in $hours hr';
      return (text: text, color: AppColors.amberDeep, icon: LucideIcons.clock);
    }
    return null;
  }

  DfPillTone _decisionTone(String decision) {
    switch (decision) {
      case 'approved':
        return DfPillTone.success;
      case 'rejected':
        return DfPillTone.danger;
      default:
        return DfPillTone.attention;
    }
  }

  IconData _decisionIcon(String decision) {
    switch (decision) {
      case 'approved':
        return LucideIcons.checkCircle2;
      case 'rejected':
        return LucideIcons.xCircle;
      default:
        return LucideIcons.eye;
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = widget.aiResult?.aiDecision ?? 'pending';
    final parentDecision = widget.aiResult?.parentDecision ?? 'pending';
    final confidence = widget.aiResult?.aiConfidence ?? 0.0;
    final reason = widget.aiResult?.aiReason ?? '';
    final parentNote = widget.aiResult?.parentNote ?? '';
    final allUrls = _allUrls;
    final expiry = _expiryWarning();

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.taskDescription,
          style: AppText.cardHeader(color: Colors.white, size: 16),
        ),
        actions: [
          // URL-expiry warning. Lives in the AppBar so it's always
          // visible while the parent is looking at the photo, without
          // overlapping the AI/parent panel below. Tapping it shows a
          // tooltip with the same text for a11y / long-text cases.
          if (expiry != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Tooltip(
                  message: expiry.text,
                  child: DfStatusPill(
                    expiry.text,
                    tone: expiry.color == AppColors.dangerFg
                        ? DfPillTone.danger
                        : DfPillTone.attention,
                    icon: expiry.icon,
                  ),
                ),
              ),
            ),
          ],
          if (allUrls.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_currentPage + 1}/${allUrls.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
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
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(allUrls.length, (i) {
                  final active = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: active ? 18 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      color: active
                          ? AppColors.greenBright
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                  );
                }),
              ),
            ),
          if (widget.aiResult != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                18,
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
              ),
              decoration: const BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.card),
                  topRight: Radius.circular(AppRadius.card),
                ),
                boxShadow: AppShadows.raised,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DfStatusPill(
                        'AI: $decision',
                        tone: _decisionTone(decision),
                        icon: _decisionIcon(decision),
                      ),
                      const Spacer(),
                      Text(
                        '${(confidence * 100).toStringAsFixed(0)}% confidence',
                        style: AppText.caption(),
                      ),
                    ],
                  ),
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(reason, style: AppText.body(size: 14)),
                  ],
                  if (parentDecision != 'pending') ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    DfStatusPill(
                      'Parent: $parentDecision',
                      tone: parentDecision == 'approved'
                          ? DfPillTone.success
                          : DfPillTone.danger,
                      icon: parentDecision == 'approved'
                          ? LucideIcons.checkCircle2
                          : LucideIcons.xCircle,
                    ),
                  ],
                  if (parentNote.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          LucideIcons.messageSquare,
                          size: 15,
                          color: AppColors.green,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            parentNote,
                            style: AppText.body(size: 14),
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
