import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/proof_service.dart';
import '../services/parent_preferences_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../widgets/proof_thumbnail.dart';
import '../widgets/shimmer_loading.dart';
import 'proof_image_viewer.dart';

/// Flat list of proofs awaiting parent review, with multi-select and
/// bulk approve / reject. The single-proof approve flow in
/// proof_image_viewer.dart is still available for one-off decisions;
/// this screen is the high-throughput path.
class PendingProofsScreen extends StatefulWidget {
  final String childId;
  final String childName;
  const PendingProofsScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<PendingProofsScreen> createState() => _PendingProofsScreenState();
}

class _PendingProofsScreenState extends State<PendingProofsScreen> {
  final _proofService = ProofService();
  final _parentPrefs = ParentPreferencesService();
  List<ProofSubmission> _proofs = [];
  bool _loading = true;
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};
  // Inline error banner state — set on load failure so the screen can
  // show a retry card instead of leaving the list empty with no
  // explanation.
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _proofs = await _proofService.getPendingProofs(widget.childId);
      await _maybeAutoApprove();
    } catch (e) {
      // Mirror the schedules_screen fix: always flip _loading off
      // (the older code only did that inside the try, so a Supabase
      // hiccup left the spinner running forever) and surface the
      // real exception so the parent can retry from the dashboard.
      _proofs = [];
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Opt-in enforcement: when the parent has auto-approve enabled,
  /// clear high-confidence AI "approved" proofs automatically so the
  /// parent only reviews the ambiguous / flagged ones. Runs under the
  /// parent JWT, so it can legitimately set parent_decision (which the
  /// kid app cannot). No-op when the pref is off or nothing qualifies.
  Future<void> _maybeAutoApprove() async {
    final enabled = await _parentPrefs.getAutoApproveMath();
    if (!enabled) return;
    final eligible = _proofs
        .where(
          (p) =>
              p.parentDecision == 'pending' &&
              p.aiDecision == 'approved' &&
              (p.aiConfidence ?? 0) >= ProofService.aiAutoApproveConfidence,
        )
        .toList();
    if (eligible.isEmpty) return;
    for (final p in eligible) {
      await _proofService.parentApprove(
        p.id,
        parentNote: 'Auto-approved (AI confident it was homework)',
      );
    }
    // Re-fetch so the auto-approved rows drop out of the pending list.
    _proofs = await _proofService.getPendingProofs(widget.childId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Auto-approved ${eligible.length} '
            '${eligible.length == 1 ? 'proof' : 'proofs'} the AI was '
            'confident about.',
          ),
        ),
      );
    }
  }

  void _toggleSelect(String proofId) {
    setState(() {
      if (_selected.contains(proofId)) {
        _selected.remove(proofId);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(proofId);
      }
    });
  }

  void _enterSelection(String proofId) {
    setState(() {
      _selectionMode = true;
      _selected.add(proofId);
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }

  /// One-tap approve/reject on a single row — the quick path next to
  /// the AI verdict, separate from the note-taking bulk flow below.
  Future<void> _quickDecide(ProofSubmission p, String decision) async {
    try {
      if (decision == 'approved') {
        await _proofService.parentApprove(p.id);
      } else {
        await _proofService.parentReject(p.id);
      }
      if (mounted) {
        setState(() {
          _proofs.removeWhere((x) => x.id == p.id);
          _selected.remove(p.id);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _bulkDecide(String decision) async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ids = _selected.toList();
    final label = decision == 'approved' ? 'Approve' : 'Reject';

    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label $count ${count == 1 ? 'proof' : 'proofs'}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              decision == 'approved'
                  ? 'These will count toward your free-sessions quota.'
                  : 'The kid will see they were rejected.',
            ),
            // Quick-reason chips for bulk reject only. Tapping fills
            // the note so the parent can still tweak before sending.
            // Approvals don't need a reason; skipping chips there
            // keeps the dialog tighter.
            if (decision == 'rejected') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final r in const [
                    'Too blurry',
                    'Wrong subject',
                    'Incomplete work',
                    'Didn\'t show the work',
                    'Try again',
                  ])
                    ActionChip(
                      label: Text(r, style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        noteController.text = r;
                        noteController.selection = TextSelection.fromPosition(
                          TextPosition(offset: noteController.text.length),
                        );
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional, sent on all selected)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: decision == 'approved'
                  ? AppColors.success
                  : AppColors.danger,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      noteController.dispose();
      return;
    }

    // Read text first, then dispose — disposing first is a silent
    // bug since the controller's backing value isn't always reset
    // and a future Flutter version could return empty.
    final noteText = noteController.text.trim();
    noteController.dispose();

    try {
      await _proofService.batchApproveOrReject(
        ids,
        decision,
        parentNote: noteText.isEmpty ? null : noteText,
      );
      if (mounted) {
        setState(() {
          _proofs.removeWhere((p) => _selected.contains(p.id));
          _selected.clear();
          _selectionMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$label successful on $count ${count == 1 ? 'proof' : 'proofs'}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  DfPillTone _aiTone(String? decision) {
    switch (decision) {
      case 'approved':
        return DfPillTone.success;
      case 'rejected':
        return DfPillTone.danger;
      default:
        return DfPillTone.attention;
    }
  }

  IconData _aiIcon(String? decision) {
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
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? '${_selected.length} selected'
              : 'Review ${widget.childName}\'s proofs',
        ),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: _clearSelection,
              )
            : null,
        actions: _selectionMode
            ? [
                IconButton(
                  tooltip: 'Select all',
                  icon: Icon(
                    _selected.length == _proofs.length
                        ? LucideIcons.listX
                        : LucideIcons.listChecks,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_selected.length == _proofs.length) {
                        _selected.clear();
                        _selectionMode = false;
                      } else {
                        _selected
                          ..clear()
                          ..addAll(_proofs.map((p) => p.id));
                      }
                    });
                  },
                ),
              ]
            : null,
      ),
      body: _buildBody(),
      bottomNavigationBar: _selectionMode && _selected.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: DfButton.danger(
                        'Reject (${_selected.length})',
                        icon: LucideIcons.x,
                        onPressed: () => _bulkDecide('rejected'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DfButton(
                        'Approve (${_selected.length})',
                        icon: LucideIcons.check,
                        onPressed: () => _bulkDecide('approved'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: List.generate(
          6,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DfCard(
              child: Row(
                children: [
                  ShimmerLoading(
                    width: 64,
                    height: 64,
                    borderRadius: AppRadius.tile,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ShimmerLoading(height: 14, width: 160),
                        const SizedBox(height: 10),
                        ShimmerLoading(height: 12, width: 90, borderRadius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DfCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  color: AppColors.dangerFg,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  'Couldn’t load pending proofs.',
                  style: AppText.cardHeader(size: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: AppText.bodySecondary(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                DfButton.outline('Try again', onPressed: _load, expand: false),
              ],
            ),
          ),
        ),
      );
    }

    if (_proofs.isEmpty) {
      return DfEmptyState(
        icon: LucideIcons.checkCheck,
        title: 'No proof photos yet',
        hint: '${widget.childName}’s next submission will show up here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.screenPadding,
        AppSpacing.screenPadding,
        96,
      ),
      itemCount: _proofs.length,
      itemBuilder: (ctx, i) {
        final p = _proofs[i];
        final selected = _selected.contains(p.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.blockGap),
          child: GestureDetector(
            onLongPress: () => _enterSelection(p.id),
            child: DfCard(
              color: selected ? AppColors.greenTint : null,
              borderColor: selected ? AppColors.green : null,
              onTap: _selectionMode
                  ? () => _toggleSelect(p.id)
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProofImageViewer(
                          imageUrl: p.imageUrl,
                          taskDescription: p.taskDescription ?? '',
                          aiResult: p,
                        ),
                      ),
                    ).then((_) => _load()),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 10, top: 4),
                      child: Icon(
                        selected
                            ? LucideIcons.checkCircle2
                            : LucideIcons.circle,
                        color: selected ? AppColors.green : AppColors.inkFaint,
                        size: 22,
                      ),
                    ),
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.tile),
                      child: p.imageUrl.isEmpty
                          ? Container(
                              color: AppColors.border2,
                              child: const Icon(
                                LucideIcons.imageOff,
                                color: AppColors.ink45,
                              ),
                            )
                          : ProofThumbnail(
                              url: p.imageUrl,
                              height: 64,
                              width: 64,
                              fit: BoxFit.cover,
                              borderRadius: BorderRadius.circular(
                                AppRadius.tile,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.taskDescription ?? '(no description)',
                          style: AppText.listTitle(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        if (p.aiDecision != null)
                          DfStatusPill(
                            p.aiConfidence != null
                                ? 'AI: ${p.aiDecision} '
                                      '(${(p.aiConfidence! * 100).round()}%)'
                                : 'AI: ${p.aiDecision}',
                            tone: _aiTone(p.aiDecision),
                            icon: _aiIcon(p.aiDecision),
                          ),
                        if (p.aiReason != null && p.aiReason!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              p.aiReason!,
                              style: AppText.caption(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!_selectionMode) ...[
                    const SizedBox(width: 4),
                    Column(
                      children: [
                        IconButton(
                          tooltip: 'Approve',
                          icon: const Icon(
                            LucideIcons.circleCheck,
                            color: AppColors.green,
                          ),
                          onPressed: () => _quickDecide(p, 'approved'),
                        ),
                        IconButton(
                          tooltip: 'Reject',
                          icon: const Icon(
                            LucideIcons.circleX,
                            color: AppColors.dangerFg,
                          ),
                          onPressed: () => _quickDecide(p, 'rejected'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
