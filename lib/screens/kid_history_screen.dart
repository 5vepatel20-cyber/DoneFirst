import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import 'proof_image_viewer.dart';

class KidHistoryScreen extends StatefulWidget {
  final String childId;
  final String childName;
  const KidHistoryScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<KidHistoryScreen> createState() => _KidHistoryScreenState();
}

class _KidHistoryScreenState extends State<KidHistoryScreen> {
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
    if (mounted) setState(() => _loading = false);
  }

  String _formatDuration(String? startedAt, String? endedAt) {
    if (startedAt == null) return '--';
    final start = DateTime.tryParse(startedAt);
    if (start == null) return '--';
    if (endedAt == null) {
      final diff = DateTime.now().difference(start);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      return h > 0 ? '${h}h ${m}m ago' : '${m}m ago';
    }
    final end = DateTime.tryParse(endedAt);
    if (end == null) return '--';
    final diff = end.difference(start);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.childName}\'s History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: 'No sessions yet',
              subtitle: 'Complete homework to see your history',
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
                final duration = _formatDuration(
                  s['started_at']?.toString(),
                  s['ended_at']?.toString(),
                );

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
                            : status == 'active'
                            ? Icons.play_circle
                            : Icons.cancel,
                        color: status == 'completed'
                            ? AppColors.success
                            : status == 'active'
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                    ),
                    title: Text(
                      date,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      '$duration - $status',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _showProofs(s['id'] as String),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showProofs(String sessionId) async {
    final proofs = await _proofService.getProofsForSession(sessionId);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Your Proofs')),
          body: proofs.isEmpty
              ? const Center(child: Text('No proofs submitted'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: proofs.length,
                  itemBuilder: (ctx, i) {
                    final p = proofs[i];
                    final imageUrl = p['image_url'] as String? ?? '';
                    final aiDecision = p['ai_decision'] ?? 'pending';
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
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (aiDecision == 'approved'
                                                ? AppColors.success
                                                : aiDecision == 'rejected'
                                                ? AppColors.danger
                                                : AppColors.accent)
                                            .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    aiDecision == 'approved'
                                        ? 'Approved'
                                        : aiDecision == 'rejected'
                                        ? 'Rejected'
                                        : 'Waiting for parent',
                                    style: TextStyle(
                                      color: aiDecision == 'approved'
                                          ? AppColors.success
                                          : aiDecision == 'rejected'
                                          ? AppColors.danger
                                          : AppColors.accent,
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
}
