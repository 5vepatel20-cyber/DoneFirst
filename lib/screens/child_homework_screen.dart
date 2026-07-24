import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/proof_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../widgets/proof_thumbnail.dart';
import '../widgets/shimmer_loading.dart';
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
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text('${widget.childName}\'s Homework'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.blockGap),
            child: DfCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ShimmerLoading(width: 90, height: 16, borderRadius: 6),
                      const Spacer(),
                      ShimmerLoading(width: 40, height: 14, borderRadius: 6),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const ShimmerLoading(height: 12, width: double.infinity),
                  const SizedBox(height: 8),
                  ShimmerLoading(height: 12, width: 180, borderRadius: 6),
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
                  'Couldn’t load homework.',
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

    if (_sessions.isEmpty) {
      return DfEmptyState(
        icon: LucideIcons.bookOpen,
        title: 'No homework sessions yet',
        hint:
            '${widget.childName}’s sessions will appear here once they '
            'start focusing.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final session = _sessions[index];
          final tasks = _tasksBySession[session.id] ?? [];
          final proofs = _proofsBySession[session.id] ?? [];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.blockGap),
            child: _SessionCard(session: session, tasks: tasks, proofs: proofs),
          );
        },
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

  DfPillTone _statusTone(String status) {
    switch (status) {
      case 'completed':
        return DfPillTone.success;
      case 'ended_by_parent':
      case 'cancelled':
        return DfPillTone.danger;
      case 'timed_out':
        return DfPillTone.attention;
      default:
        return DfPillTone.neutral;
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

  DfPillTone _taskTone(String status) {
    switch (status) {
      case 'approved':
        return DfPillTone.success;
      case 'rejected':
        return DfPillTone.danger;
      case 'submitted':
        return DfPillTone.info;
      default:
        return DfPillTone.neutral;
    }
  }

  DfPillTone _proofTone(String? decision) {
    switch (decision) {
      case 'approved':
        return DfPillTone.success;
      case 'rejected':
        return DfPillTone.danger;
      case 'needs_review':
        return DfPillTone.attention;
      default:
        return DfPillTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = tasks.where((t) => !t.isPending).length;
    final approvedCount = proofs
        .where((p) => p.aiDecision == 'approved')
        .length;
    final sessionDate = session.startedAt;
    final dateStr =
        '${sessionDate.month}/${sessionDate.day}/${sessionDate.year}';

    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _statusIcon(session.status),
                  size: 18,
                  color: AppColors.ink70,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateStr, style: AppText.cardHeader(size: 15)),
                    const SizedBox(height: 4),
                    DfStatusPill(
                      _statusLabel(session.status),
                      tone: _statusTone(session.status),
                    ),
                  ],
                ),
              ),
              if (session.endedAt != null)
                Text(
                  '${session.endedAt!.difference(session.startedAt).inMinutes}m',
                  style: AppText.caption(),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          // Tasks summary
          if (tasks.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  LucideIcons.listChecks,
                  size: 15,
                  color: AppColors.amber,
                ),
                const SizedBox(width: 6),
                Text(
                  'Tasks · $doneCount/${tasks.length} done',
                  style: AppText.body(size: 13, w: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...tasks.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      t.isPending
                          ? LucideIcons.circle
                          : LucideIcons.circleCheck,
                      size: 14,
                      color: t.isPending ? AppColors.ink45 : AppColors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.description,
                        style: AppText.body(
                          size: 13,
                          color: t.isPending ? AppColors.ink45 : AppColors.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    DfStatusPill(t.status, tone: _taskTone(t.status)),
                  ],
                ),
              ),
            ),
          ] else
            Row(
              children: [
                const Icon(
                  LucideIcons.listChecks,
                  size: 15,
                  color: AppColors.ink45,
                ),
                const SizedBox(width: 6),
                Text('No tasks', style: AppText.bodySecondary()),
              ],
            ),
          // Proofs
          if (proofs.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(LucideIcons.image, size: 15, color: AppColors.amber),
                const SizedBox(width: 6),
                Text(
                  'Proofs · $approvedCount/${proofs.length} approved',
                  style: AppText.body(size: 13, w: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: proofs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          child: ProofThumbnail(
                            url: p.imageUrl,
                            height: 54,
                            width: 54,
                            borderRadius: BorderRadius.circular(
                              AppRadius.small,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        DfStatusPill(
                          p.aiDecision ?? 'pending',
                          tone: _proofTone(p.aiDecision),
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
    );
  }
}
