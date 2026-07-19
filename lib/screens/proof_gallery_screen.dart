import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/proof_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/proof_thumbnail.dart';
import '../widgets/empty_state.dart';
import 'proof_image_viewer.dart';

class ProofGalleryScreen extends StatefulWidget {
  final String childId;
  final String childName;
  const ProofGalleryScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<ProofGalleryScreen> createState() => _ProofGalleryScreenState();
}

class _ProofGalleryScreenState extends State<ProofGalleryScreen> {
  final _sessionService = SessionService();
  final _proofService = ProofService();
  final List<_ProofWithDate> _allProofs = [];
  bool _loading = true;
  // null = show every status. One of 'approved' | 'rejected' |
  // 'pending' to filter the grid. Decoupled from the enum used by
  // the model so we can show a friendly "All" pill without a
  // fourth enum value.
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await _sessionService.getHistory(widget.childId);
      // Build a date-by-session index up front so we can attribute
      // each proof to its session's start date in O(1) instead of
      // re-deriving it for every row.
      final dateBySession = <String, String>{
        for (final s in sessions)
          s.id: s.startedAt.toIso8601String().substring(0, 10),
      };
      // Pull proofs in parallel for every session instead of one
      // round-trip per session. With N sessions of M proofs each,
      // this drops from N+1 round-trips to ~N parallel queries.
      final proofLists = await Future.wait(
        sessions.map((s) => _proofService.getProofsForSession(s.id)),
      );
      final allProofs = <_ProofWithDate>[];
      for (var i = 0; i < sessions.length; i++) {
        final date = dateBySession[sessions[i].id] ?? '';
        for (final p in proofLists[i]) {
          allProofs.add(_ProofWithDate(p, date));
        }
      }
      if (mounted) {
        setState(() {
          _allProofs.clear();
          _allProofs.addAll(allProofs);
        });
      }
    } catch (e) {
      // Same spinner-forever pattern as pending_proofs_screen +
      // schedules_screen — always flip _loading off in finally so a
      // Supabase hiccup doesn't leave the user staring at shimmer
      // tiles forever, and surface the real exception.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn’t load proof gallery: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The proof list after the active status filter is applied.
  /// Computed on every build — _allProofs is bounded by the kid's
  /// lifetime history, so this is cheap.
  List<_ProofWithDate> get _filteredProofs {
    final filter = _statusFilter;
    if (filter == null) return _allProofs;
    return _allProofs.where((pw) {
      final p = pw.proof;
      switch (filter) {
        case 'approved':
          return p.isApproved;
        case 'rejected':
          return p.isRejected;
        case 'pending':
          return p.isPending;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProofs;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.childName}\'s Proofs')),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: GridView(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                children: List.generate(9, (_) => ShimmerLoading(borderRadius: 4)),
              ),
            )
          : _allProofs.isEmpty
          ? const EmptyState(
              icon: LucideIcons.image,
              title: 'No proof photos yet',
              subtitle: 'Proofs appear here after submission',
            )
          : Column(
              children: [
                // Status filter chips. Mirrors the chip row on
                // proof_review_screen so parents have the same
                // vocabulary across screens. Lives in a horizontal
                // scroll so the row survives small screens / long
                // future status lists.
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    children: [
                      _filterChip('All', null),
                      const SizedBox(width: 4),
                      _filterChip('Approved', 'approved'),
                      const SizedBox(width: 4),
                      _filterChip('Rejected', 'rejected'),
                      const SizedBox(width: 4),
                      _filterChip('Pending', 'pending'),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No proofs match this filter',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(8),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 4,
                              mainAxisSpacing: 4,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final pw = filtered[i];
                              final p = pw.proof;
                              final allUrls = p.imageUrls.isNotEmpty
                                  ? p.imageUrls
                                  : [p.imageUrl];
                              final photoCount = allUrls.length;

                              final borderColor = p.isApproved
                                  ? AppColors.success
                                  : p.isRejected
                                  ? AppColors.danger
                                  : p.aiDecision == 'approved'
                                  ? AppColors.info
                                  : AppColors.accent;

                              return GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProofImageViewer(
                                      imageUrl: allUrls.first,
                                      taskDescription:
                                          p.taskDescription ?? '',
                                      aiResult: p,
                                    ),
                                  ),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: borderColor,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ProofThumbnail(
                                        url: allUrls.first,
                                        fit: BoxFit.cover,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          color: Colors.black54,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                pw.date,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                ),
                                              ),
                                              if (photoCount > 1)
                                                Text(
                                                  '1/$photoCount',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (p.isApproved)
                                        const Positioned(
                                          top: 2,
                                          right: 2,
                                          child: Icon(
                                            LucideIcons.checkCircle2,
                                            color: AppColors.success,
                                            size: 16,
                                          ),
                                        ),
                                      if (p.isRejected)
                                        const Positioned(
                                          top: 2,
                                          right: 2,
                                          child: Icon(
                                            LucideIcons.xCircle,
                                            color: AppColors.danger,
                                            size: 16,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _filterChip(String label, String? value) {
    final isSelected = _statusFilter == value;
    return InkWell(
      onTap: () => setState(() => _statusFilter = value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.textSecondary.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ProofWithDate {
  final ProofSubmission proof;
  final String date;
  const _ProofWithDate(this.proof, this.date);
}