import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
import 'proof_image_viewer.dart';

class ProofReviewScreen extends StatefulWidget {
  final String childId;
  const ProofReviewScreen({super.key, required this.childId});

  @override
  State<ProofReviewScreen> createState() => _ProofReviewScreenState();
}

class _ProofReviewScreenState extends State<ProofReviewScreen> {
  final _sessionService = SessionService();
  final _proofService = ProofService();
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _sessions = await _sessionService.getHistory(widget.childId);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
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
                      Icons.history,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No sessions yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Complete a lock session to see history',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sessions.length,
              itemBuilder: (ctx, i) {
                final s = _sessions[i];
                final status = s['status'] ?? 'unknown';
                final started = s['started_at']?.toString() ?? '';
                final date = started.length >= 10
                    ? started.substring(0, 10)
                    : started;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            (status == 'completed'
                                    ? AppColors.success
                                    : AppColors.accent)
                                .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        status == 'completed'
                            ? Icons.check_circle
                            : Icons.play_circle,
                        color: status == 'completed'
                            ? AppColors.success
                            : AppColors.accent,
                      ),
                    ),
                    title: Text(
                      '$status — $date',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      'Min: ${s['min_lock_minutes']}m | ${s['approval_mode']}',
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _showSessionProofs(s['id'] as String),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showSessionProofs(String sessionId) async {
    final proofs = await _proofService.getProofsForSession(sessionId);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Proofs')),
          body: proofs.isEmpty
              ? const Center(child: Text('No proofs submitted'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: proofs.length,
                  itemBuilder: (ctx, i) {
                    final p = proofs[i];
                    final imageUrl = p['image_url'] as String? ?? '';
                    final aiDecision = p['ai_decision'] ?? 'pending';
                    final parentDecision = p['parent_decision'] ?? 'pending';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imageUrl.isNotEmpty)
                            GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProofImageViewer(
                                    imageUrl: imageUrl,
                                    taskDescription:
                                        p['task_description'] as String? ?? '',
                                    aiResult: p,
                                  ),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                ),
                                child: Image.network(
                                  imageUrl,
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['task_description'] as String? ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    _smallBadge(
                                      'AI: $aiDecision',
                                      aiDecision == 'approved'
                                          ? AppColors.success
                                          : aiDecision == 'rejected'
                                          ? AppColors.danger
                                          : AppColors.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    _smallBadge(
                                      'Parent: $parentDecision',
                                      parentDecision == 'approved'
                                          ? AppColors.success
                                          : parentDecision == 'rejected'
                                          ? AppColors.danger
                                          : AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                                if (p['ai_reason'] != null &&
                                    (p['ai_reason'] as String).isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      p['ai_reason'],
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _smallBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}
