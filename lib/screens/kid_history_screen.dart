import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_banner.dart';
import '../widgets/proof_thumbnail.dart';
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
  List<HomeworkSession> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _sessions = await _sessionService.getHistory(widget.childId);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  String _formatDuration(HomeworkSession s) {
    final diff = s.endedAt != null
        ? s.endedAt!.difference(s.startedAt)
        : DateTime.now().difference(s.startedAt);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My history', style: AppText.screenTitle()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? RetryWidget(message: _error!, onRetry: _load)
          : _sessions.isEmpty
          ? const EmptyState(
              icon: LucideIcons.history,
              title: 'No sessions yet',
              subtitle: 'Complete homework to see your history',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sessions.length,
              itemBuilder: (ctx, i) {
                final s = _sessions[i];
                final started = s.startedAt.toIso8601String();
                final date = started.length >= 10
                    ? started.substring(0, 10)
                    : started;
                final duration = _formatDuration(s);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            (s.isCompleted
                                    ? AppColors.success
                                    : AppColors.accent)
                                .withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        s.isCompleted
                            ? LucideIcons.checkCircle2
                            : s.isActive
                            ? LucideIcons.playCircle
                            : LucideIcons.xCircle,
                        color: s.isCompleted
                            ? AppColors.success
                            : s.isActive
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                    ),
                    title: Text(
                      date,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      '$duration - ${s.status}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    onTap: () => _showProofs(s.id),
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
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (p.imageUrl.isNotEmpty)
                            GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProofImageViewer(
                                    imageUrl: p.imageUrl,
                                    taskDescription:
                                        p.taskDescription ?? '',
                                    aiResult: p,
                                  ),
                                ),
                              ),
                              child: ProofThumbnail(
                                url: p.imageUrl,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.taskDescription ?? '',
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
                                        (p.aiDecision == 'approved'
                                                ? AppColors.success
                                                : p.aiDecision == 'rejected'
                                                ? AppColors.danger
                                                : AppColors.accent)
                                            .withValues(alpha:0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    p.isApproved
                                        ? 'Approved'
                                        : p.isRejected
                                        ? 'Rejected'
                                        : 'Waiting for parent',
                                    style: TextStyle(
                                      color: p.isApproved
                                          ? AppColors.success
                                          : p.isRejected
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
