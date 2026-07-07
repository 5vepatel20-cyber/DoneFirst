import 'package:flutter/material.dart';
import '../services/proof_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
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
  List<Map<String, dynamic>> _allProofs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await _sessionService.getHistory(widget.childId);
    final allProofs = <Map<String, dynamic>>[];
    for (final s in sessions) {
      final proofs = await _proofService.getProofsForSession(s['id'] as String);
      for (final p in proofs) {
        p['session_date'] =
            (s['started_at'] as String?)?.substring(0, 10) ?? '';
        allProofs.add(p);
      }
    }
    if (mounted)
      setState(() {
        _allProofs = allProofs;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.childName}\'s Proofs')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _allProofs.isEmpty
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
                  final p = _allProofs[i];
                  final imageUrl = p['image_url'] as String? ?? '';
                  final imageUrls =
                      (p['image_urls'] as List<dynamic>?)
                          ?.map((e) => e.toString())
                          .toList() ??
                      [];
                  final aiDecision = p['ai_decision'] as String? ?? 'pending';
                  final parentDecision =
                      p['parent_decision'] as String? ?? 'pending';
                  final taskDesc = p['task_description'] as String? ?? '';
                  final allUrls = imageUrls.isNotEmpty ? imageUrls : [imageUrl];
                  final photoCount = allUrls.length;

                  final borderColor = parentDecision == 'approved'
                      ? AppColors.success
                      : parentDecision == 'rejected'
                      ? AppColors.danger
                      : aiDecision == 'approved'
                      ? AppColors.info
                      : AppColors.accent;

                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProofImageViewer(
                          imageUrl: allUrls.first,
                          taskDescription: taskDesc,
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
                                    p['session_date'] as String? ?? '',
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
                          if (parentDecision == 'approved')
                            const Positioned(
                              top: 2,
                              right: 2,
                              child: Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                                size: 16,
                              ),
                            ),
                          if (parentDecision == 'rejected')
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
