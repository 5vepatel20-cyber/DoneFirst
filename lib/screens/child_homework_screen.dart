import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/proof_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../utils/subjects.dart';
import '../widgets/proof_thumbnail.dart';
import 'proof_image_viewer.dart';

/// Parent-side screen showing all homework tasks and proof submissions
/// for a specific child across their sessions.
class ChildHomeworkScreen extends StatefulWidget {
  final String childId;
  final String childName;
  const ChildHomeworkScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<ChildHomeworkScreen> createState() => _ChildHomeworkScreenState();
}

class _ChildHomeworkScreenState extends State<ChildHomeworkScreen> {
  final _proofService = ProofService();
  final _sessionService = SessionService();
  List<HomeworkSession> _sessions = [];
  final Map<String, List<HomeworkTask>> _tasksBySession = {};
  final Map<String, List<ProofSubmission>> _proofsBySession = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sessions = await _sessionService.getHistory(widget.childId);
      _sessions = sessions;

      final results = await Future.wait(
        sessions.map((s) async {
          final tasks = await _proofService.getTasks(s.id);
          final proofs = await _proofService.getProofsForSession(s.id);
          return MapEntry(s.id, (tasks, proofs));
        }),
      );

      for (final entry in results) {
        _tasksBySession[entry.key] = entry.value.$1;
        _proofsBySession[entry.key] = entry.value.$2;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load homework: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName}\'s Homework'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.bookOpen,
                        size: 48,
                        color: AppColors.muted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No homework sessions yet',
                        style: AppText.body(color: AppColors.muted),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final tasks = _tasksBySession[session.id] ?? [];
                      final proofs = _proofsBySession[session.id] ?? [];
                      return _SessionCard(
                        session: session,
                        tasks: tasks,
                        proofs: proofs,
                      );
                    },
                  ),
                ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final HomeworkSession session;
  final List<HomeworkTask> tasks;
  final List<ProofSubmission> proofs;

  const _SessionCard({
    required this.session,
    required this.tasks,
    required this.proofs,
  });

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'ended_by_parent':
        return 'Ended by parent';
      case 'timed_out':
        return 'Timed out';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return LucideIcons.circleCheck;
      case 'ended_by_parent':
        return LucideIcons.circleX;
      case 'timed_out':
        return LucideIcons.clock;
      case 'cancelled':
        return LucideIcons.ban;
      default:
        return LucideIcons.circle;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'ended_by_parent':
      case 'cancelled':
        return AppColors.danger;
      case 'timed_out':
        return AppColors.warn;
      default:
        return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = tasks.where((t) => !t.isPending).length;
    final approvedCount = proofs.where((p) => p.aiDecision == 'approved').length;
    final sessionDate = session.startedAt;
    final dateStr =
        '${sessionDate.month}/${sessionDate.day}/${sessionDate.year}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(session.status),
                    size: 18, color: _statusColor(session.status)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateStr,
                          style: AppText.body(
                              size: 14, color: AppColors.textPrimary)
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        _statusLabel(session.status),
                        style: AppText.bodySecondary(
                            size: 12, color: _statusColor(session.status)),
                      ),
                    ],
                  ),
                ),
                if (session.endedAt != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${session.endedAt!.difference(session.startedAt).inMinutes}m',
                    style:
                        AppText.bodySecondary(size: 12, color: AppColors.muted),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Tasks summary
            if (tasks.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(LucideIcons.listChecks,
                      size: 15, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Tasks: $doneCount/${tasks.length} done',
                    style: AppText.body(
                        size: 13, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...tasks.map((t) => Padding(
                    padding: const EdgeInsets.only(left: 21),
                    child: Row(
                      children: [
                        Icon(
                          t.isPending
                              ? LucideIcons.circle
                              : LucideIcons.circleCheck,
                          size: 13,
                          color: t.isPending
                              ? AppColors.muted
                              : AppColors.success,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t.description,
                            style: AppText.body(
                              size: 12,
                              color: t.isPending
                                  ? AppColors.muted
                                  : AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: _taskStatusColor(t.status).withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            t.status,
                            style: AppText.body(
                                size: 10,
                                color: _taskStatusColor(t.status)),
                          ),
                        ),
                      ],
                    ),
                  )),
            ] else ...[
              Row(
                children: [
                  const Icon(LucideIcons.listChecks,
                      size: 15, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Text(
                    'No tasks',
                    style:
                        AppText.bodySecondary(size: 13, color: AppColors.muted),
                  ),
                ],
              ),
            ],
            // Proofs
            if (proofs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(LucideIcons.image,
                      size: 15, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Proofs: $approvedCount/${proofs.length} approved',
                    style: AppText.body(
                        size: 13, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: proofs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = proofs[i];
                    return GestureDetector(
                      onTap: () {
                        final url = p.imageUrl.isNotEmpty
                            ? p.imageUrl
                            : (p.imageUrls.isNotEmpty ? p.imageUrls.first : '');
                        if (url.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProofImageViewer(
                                imageUrl: url,
                                taskDescription: p.taskDescription ?? '',
                                aiResult: p,
                              ),
                            ),
                          );
                        }
                      },
                      child: Column(
                        children: [
                          ProofThumbnail(url: p.imageUrl),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color:
                                  _proofDecisionColor(p.aiDecision).withAlpha(30),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              p.aiDecision ?? 'pending',
                              style: AppText.body(
                                  size: 9,
                                  color: _proofDecisionColor(p.aiDecision)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _taskStatusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.danger;
      case 'submitted':
        return AppColors.accent;
      default:
        return AppColors.muted;
    }
  }

  Color _proofDecisionColor(String? decision) {
    switch (decision) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.danger;
      case 'needs_review':
        return AppColors.warn;
      default:
        return AppColors.muted;
    }
  }
}
