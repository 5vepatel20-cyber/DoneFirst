import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/proof_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shimmer_loading.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await _sessionService.getHistory(widget.childId);
    final allProofs = <_ProofWithDate>[];
    for (final s in sessions) {
      final proofs = await _proofService.getProofsForSession(s.id);
      final date = s.startedAt.toIso8601String().substring(0, 10);
      for (final p in proofs) {
        allProofs.add(_ProofWithDate(p, date));
      }
    }
    if (mounted)
      setState(() {
        _allProofs.clear();
        _allProofs.addAll(allProofs);
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
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
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha:0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.photo_library,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No proof photos yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Proofs appear here after submission',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: _allProofs.length,
                  itemBuilder: (ctx, i) {
                  final pw = _allProofs[i];
                  final p = pw.proof;
                  final allUrls = p.imageUrls.isNotEmpty ? p.imageUrls : [p.imageUrl];
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
                          taskDescription: p.taskDescription ?? '',
                          aiResult: p,
                        ),
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: borderColor, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: Image.network(
                              allUrls.first,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: Colors.grey.shade200),
                            ),
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
                                Icons.check_circle,
                                color: AppColors.success,
                                size: 16,
                              ),
                            ),
                          if (p.isRejected)
                            const Positioned(
                              top: 2,
                              right: 2,
                              child: Icon(
                                Icons.cancel,
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
    );
  }
}

class _ProofWithDate {
  final ProofSubmission proof;
  final String date;
  const _ProofWithDate(this.proof, this.date);
}
