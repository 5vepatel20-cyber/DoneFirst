import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
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
  List<ProofSubmission> _proofs = [];
  bool _loading = true;
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _proofs = await _proofService.getPendingProofs(widget.childId);
    } catch (_) {
      _proofs = [];
    }
    if (mounted) setState(() => _loading = false);
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
              backgroundColor:
                  decision == 'approved' ? AppColors.success : AppColors.danger,
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
            content: Text('$label successful on $count ${count == 1 ? 'proof' : 'proofs'}.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? '${_selected.length} selected'
              : 'Review ${widget.childName}\'s proofs',
          style: AppText.screenTitle(),
        ),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(LucideIcons.x, size: 20),
                onPressed: _clearSelection,
              )
            : null,
        actions: _selectionMode
            ? [
                IconButton(
                  tooltip: 'Select all',
                  icon: Icon(
                    _selected.length == _proofs.length
                        ? LucideIcons.squareMinus
                        : LucideIcons.squareCheckBig,
                    size: 20,
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
      body: _loading
          ? ListView(
              padding: const EdgeInsets.all(8),
              children: List.generate(
                6,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: ShimmerLoading(
                    height: 96,
                    borderRadius: 8,
                  ),
                ),
              ),
            )
          : _proofs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.checkCheck,
                          size: 48,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Inbox zero',
                        style: AppText.cardHeader(size: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'No proofs waiting for review.',
                        style: AppText.bodySecondary(),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                  itemCount: _proofs.length,
                  itemBuilder: (ctx, i) {
                    final p = _proofs[i];
                    final selected = _selected.contains(p.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: InkWell(
                        onTap: _selectionMode
                            ? () => _toggleSelect(p.id)
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProofImageViewer(
                                      imageUrl: p.imageUrl,
                                      taskDescription:
                                          p.taskDescription ?? '',
                                      aiResult: p,
                                    ),
                                  ),
                                ).then((_) => _load()),
                        onLongPress: () => _enterSelection(p.id),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_selectionMode)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    top: 4,
                                  ),
                                  child: Icon(
                                    selected
                                        ? LucideIcons.circleCheckBig
                                        : LucideIcons.circle,
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    size: 22,
                                  ),
                                ),
                              SizedBox(
                                width: 80,
                                height: 80,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: p.imageUrl.isEmpty
                                      ? Container(
                                          color: AppColors.border,
                                          child: const Icon(
                                            LucideIcons.imageOff,
                                            color: AppColors.textSecondary,
                                          ),
                                        )
                                      : ProofThumbnail(
                                          url: p.imageUrl,
                                          height: 80,
                                          width: 80,
                                          fit: BoxFit.cover,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.taskDescription ?? '(no description)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (p.aiDecision != null)
                                          _badge(
                                            'AI: ${p.aiDecision}',
                                            p.aiDecision == 'approved'
                                                ? AppColors.success
                                                : p.aiDecision == 'rejected'
                                                    ? AppColors.danger
                                                    : AppColors.accent,
                                          ),
                                      ],
                                    ),
                                    if (p.aiReason != null &&
                                        p.aiReason!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          p.aiReason!,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: _selectionMode && _selected.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _bulkDecide('rejected'),
                        icon: const Icon(LucideIcons.x,
                            size: 18, color: AppColors.danger),
                        label: Text(
                          'Reject (${_selected.length})',
                          style: const TextStyle(color: AppColors.danger),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.danger),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _bulkDecide('approved'),
                        icon: const Icon(LucideIcons.check, size: 18),
                        label: Text('Approve (${_selected.length})'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}