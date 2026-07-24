import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/proof_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/proof_thumbnail.dart';
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
  // Inline error banner state — set on load failure.
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
      _error = e.toString();
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

  Color _borderColorFor(ProofSubmission p) {
    if (p.isApproved) return AppColors.green;
    if (p.isRejected) return AppColors.dangerFg;
    if (p.aiDecision == 'approved') return AppColors.infoFg;
    return AppColors.amber;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProofs;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: Text('${widget.childName}\'s Proofs')),
      body: _buildBody(filtered),
    );
  }

  Widget _buildBody(List<_ProofWithDate> filtered) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: GridView(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          children: List.generate(
            9,
            (_) => ShimmerLoading(borderRadius: AppRadius.tile),
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
                  'Couldn’t load the proof gallery.',
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

    if (_allProofs.isEmpty) {
      return const DfEmptyState(
        icon: LucideIcons.image,
        title: 'No proof photos yet',
        hint: 'Proofs appear here after submission',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            14,
            AppSpacing.screenPadding,
            0,
          ),
          child: DfSectionLabel(
            '${filtered.length} ${filtered.length == 1 ? 'photo' : 'photos'}',
          ),
        ),
        // Status filter chips. Mirrors the chip row on
        // proof_review_screen so parents have the same vocabulary
        // across screens. Lives in a horizontal scroll so the row
        // survives small screens / long future status lists.
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
              vertical: 4,
            ),
            children: [
              DfChip(
                'All',
                selected: _statusFilter == null,
                onTap: () => setState(() => _statusFilter = null),
              ),
              const SizedBox(width: 8),
              DfChip(
                'Approved',
                selected: _statusFilter == 'approved',
                onTap: () => setState(() => _statusFilter = 'approved'),
              ),
              const SizedBox(width: 8),
              DfChip(
                'Rejected',
                selected: _statusFilter == 'rejected',
                onTap: () => setState(() => _statusFilter = 'rejected'),
              ),
              const SizedBox(width: 8),
              DfChip(
                'Pending',
                selected: _statusFilter == 'pending',
                onTap: () => setState(() => _statusFilter = 'pending'),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No proofs match this filter',
                    style: AppText.bodySecondary(),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(AppSpacing.screenPadding),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final pw = filtered[i];
                      final p = pw.proof;
                      final allUrls = p.imageUrls.isNotEmpty
                          ? p.imageUrls
                          : [p.imageUrl];
                      final photoCount = allUrls.length;
                      final borderColor = _borderColorFor(p);

                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProofImageViewer(
                              imageUrl: allUrls.first,
                              taskDescription: p.taskDescription ?? '',
                              aiResult: p,
                            ),
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: borderColor, width: 2),
                            borderRadius: BorderRadius.circular(AppRadius.tile),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ProofThumbnail(
                                url: allUrls.first,
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.tile - 2,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.ink.withValues(
                                      alpha: 0.55,
                                    ),
                                    borderRadius: BorderRadius.only(
                                      bottomLeft: Radius.circular(
                                        AppRadius.tile - 2,
                                      ),
                                      bottomRight: Radius.circular(
                                        AppRadius.tile - 2,
                                      ),
                                    ),
                                  ),
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
                                  top: 4,
                                  right: 4,
                                  child: Icon(
                                    LucideIcons.checkCircle2,
                                    color: AppColors.green,
                                    size: 16,
                                  ),
                                ),
                              if (p.isRejected)
                                const Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Icon(
                                    LucideIcons.xCircle,
                                    color: AppColors.dangerFg,
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
    );
  }
}

class _ProofWithDate {
  final ProofSubmission proof;
  final String date;
  const _ProofWithDate(this.proof, this.date);
}
