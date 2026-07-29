import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
import '../utils/subjects.dart';
import '../widgets/df_kit.dart';
import '../widgets/proof_thumbnail.dart';
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
  List<HomeworkSession> _allSessions = [];
  List<HomeworkSession> _filteredSessions = [];
  bool _loading = true;
  String? _error;

  DateTimeRange? _dateRange;
  final _searchController = TextEditingController();
  // Filter chip selection. null = all sessions, otherwise a function
  // on HomeworkSession that returns true if the session belongs in
  // the filtered set. Keeping it as a predicate (not an enum string)
  // means the chip row can be extended without touching the model.
  bool Function(HomeworkSession)? _statusFilter;
  // Per-session subject index, populated in _load(). A session
  // "matches" a subject filter if any of its tasks used that subject.
  final Map<String, Set<String>> _sessionSubjects = {};
  // Per-session search index — concatenated lowercase task descriptions.
  // Lets the search box match on what the kid actually wrote (e.g.
  // "math" or "essay") instead of only status / approval mode strings.
  final Map<String, String> _sessionSearchText = {};
  // null = show all subjects. Otherwise one of kSubjects.
  String? _subjectFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _allSessions = await _sessionService.getHistory(widget.childId);
      // Build a session-id → set-of-subjects index so the subject
      // filter is O(1) per session instead of re-querying tasks
      // for every chip tap.
      _sessionSubjects.clear();
      _sessionSearchText.clear();
      if (_allSessions.isNotEmpty) {
        // Fan out per-session task fetches in parallel. The
        // previous version awaited each session in turn inside a
        // for loop — for a kid with N sessions that's N sequential
        // round-trips. On a slow connection the search index took
        // noticeable time to populate. N independent awaits in
        // parallel collapses the total to one round-trip's worth.
        final perSessionTasks = await Future.wait(
          _allSessions.map((s) => _proofService.getTasks(s.id)),
        );
        for (var i = 0; i < _allSessions.length; i++) {
          final s = _allSessions[i];
          final tasks = perSessionTasks[i];
          _sessionSubjects[s.id] = tasks
              .map((t) => normalizeSubject(t.subject))
              .toSet();
          // Concatenate task descriptions into one searchable string
          // per session. Tokenizing is unnecessary — substring match
          // (contains) is what the filter below uses, and the index
          // is built once at load time so each keystroke stays O(N).
          _sessionSearchText[s.id] = tasks
              .map((t) => t.description)
              .join(' ')
              .toLowerCase();
        }
      }
      _applyFilters();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _applyFilters() {
    var filtered = _allSessions;
    if (_dateRange != null) {
      filtered = filtered.where((s) {
        return s.startedAt.isAfter(
              _dateRange!.start.subtract(const Duration(days: 1)),
            ) &&
            s.startedAt.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      // Match on any of: session status (e.g. "active", "completed"),
      // approval mode (e.g. "balanced", "strict"), or anything the
      // kid typed in a task description (e.g. "math", "essay"). The
      // description index is built once in _load() so this stays O(N).
      filtered = filtered
          .where(
            (s) =>
                s.status.toLowerCase().contains(query) ||
                s.approvalMode.toLowerCase().contains(query) ||
                (_sessionSearchText[s.id] ?? '').contains(query),
          )
          .toList();
    }
    final statusFilter = _statusFilter;
    if (statusFilter != null) {
      filtered = filtered.where(statusFilter).toList();
    }
    final subjectFilter = _subjectFilter;
    if (subjectFilter != null) {
      filtered = filtered.where((s) {
        // Session matches if any of its tasks used this subject.
        // A session with no tasks at all is hidden when a subject
        // filter is active — there's nothing to show for "Math"
        // if the session never had a Math task.
        return _sessionSubjects[s.id]?.contains(subjectFilter) ?? false;
      }).toList();
    }
    setState(() => _filteredSessions = filtered);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      _dateRange = picked;
      _applyFilters();
    }
  }

  void _clearFilters() {
    _dateRange = null;
    _searchController.clear();
    _statusFilter = null;
    _subjectFilter = null;
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text('Session history', style: AppText.screenTitle()),
        actions: [
          if (_dateRange != null || _searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.filterX, size: 18),
              onPressed: _clearFilters,
              tooltip: 'Clear filters',
            ),
        ],
      ),
      body: _loading
          ? _buildLoading()
          : _error != null
          ? _buildError()
          : Column(
              children: [
                _buildFilters(),
                Expanded(
                  child: _filteredSessions.isEmpty
                      ? DfEmptyState(
                          icon: LucideIcons.history,
                          title: 'No sessions found',
                          hint: _allSessions.isEmpty
                              ? 'Finished focus sessions will show up here.'
                              : 'Try adjusting your filters.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(
                            AppSpacing.screenPadding,
                          ),
                          itemCount: _filteredSessions.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, i) =>
                              _buildSessionCard(_filteredSessions[i]),
                        ),
                ),
              ],
            ),
    );
  }

  // ── Loading / Error states ──────────────────────────────────────────
  Widget _buildLoading() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => DfCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.border2,
                borderRadius: BorderRadius.circular(AppRadius.iconTile),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 12, width: 140, color: AppColors.border2),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 90, color: AppColors.border2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: DfCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.circleAlert,
                size: 28,
                color: AppColors.dangerFg,
              ),
              const SizedBox(height: 12),
              Text(
                _error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 14),
              ),
              const SizedBox(height: 16),
              DfButton.outline('Try again', expand: false, onPressed: _load),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter bar ──────────────────────────────────────────────────────
  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            12,
            AppSpacing.screenPadding,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search tasks, status…',
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              _applyFilters();
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  style: AppText.body(size: 14),
                  onChanged: (_) => _applyFilters(),
                ),
              ),
              const SizedBox(width: 8),
              DfButton.outline(
                _dateRange != null
                    ? '${_dateRange!.start.month}/${_dateRange!.start.day}'
                    : 'Dates',
                icon: LucideIcons.calendar,
                expand: false,
                onPressed: _pickDateRange,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Result count + status chip row.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: Row(
            children: [
              Text(
                _allSessions.isEmpty
                    ? ''
                    : 'Showing ${_filteredSessions.length} of '
                          '${_allSessions.length}',
                style: AppText.caption(),
              ),
              const Spacer(),
              _statusChip('All', null),
              const SizedBox(width: 6),
              _statusChip('Active', (s) => !s.isCompleted),
              const SizedBox(width: 6),
              _statusChip('Completed', (s) => s.isCompleted),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Subject filter row — horizontally scrollable.
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            children: [
              _subjectChip('All subjects', null),
              ...kSubjects.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _subjectChip(s, s),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildSessionCard(HomeworkSession s) {
    final date = s.startedAt.toIso8601String().substring(0, 10);
    final subjects = _sessionSubjects[s.id] ?? const <String>{};
    return DfCard(
      onTap: () => _showSessionProofs(s.id),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: s.isCompleted ? AppColors.greenTint : AppColors.amberTint,
              borderRadius: BorderRadius.circular(AppRadius.iconTile),
            ),
            alignment: Alignment.center,
            child: Icon(
              s.isCompleted ? LucideIcons.checkCircle2 : LucideIcons.playCircle,
              size: 20,
              color: s.isCompleted ? AppColors.green : AppColors.amberDeep,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(date, style: AppText.listTitle(size: 15)),
                    ),
                    DfStatusPill(
                      s.isCompleted ? 'Completed' : 'Active',
                      tone: s.isCompleted
                          ? DfPillTone.success
                          : DfPillTone.attention,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.minLockMinutes}m · ${s.approvalMode}',
                  style: AppText.bodySecondary(size: 12.5),
                ),
                if (subjects.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: subjects
                        .map((subj) => DfStatusPill(subj))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 6, top: 2),
            child: Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.ink45,
            ),
          ),
        ],
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
          backgroundColor: AppColors.paper,
          appBar: AppBar(title: Text('Proofs', style: AppText.screenTitle())),
          body: proofs.isEmpty
              ? const DfEmptyState(
                  icon: LucideIcons.imageOff,
                  title: 'No proofs submitted',
                  hint: 'This session has no proof photos yet.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  itemCount: proofs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) => _buildProofDetailCard(proofs[i]),
                ),
        ),
      ),
    );
  }

  /// The "Review proof" card blown up — big image, AI decision +
  /// confidence + reason (info tone), parent decision, and note.
  Widget _buildProofDetailCard(ProofSubmission p) {
    final aiDecision = p.aiDecision ?? 'pending';
    final confidence = p.aiConfidence;
    final (verdict, _) = switch (aiDecision) {
      'approved' => ('Looks like real homework', DfPillTone.success),
      'rejected' => ('Needs another look', DfPillTone.danger),
      'needs_review' => ('Worth a closer look', DfPillTone.attention),
      _ => ('Checking the photo…', DfPillTone.info),
    };
    final parentTone = p.isApproved
        ? DfPillTone.success
        : p.isRejected
        ? DfPillTone.danger
        : DfPillTone.neutral;
    return DfCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.imageUrl.isNotEmpty) ...[
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProofImageViewer(
                    imageUrl: p.imageUrl,
                    taskDescription: p.taskDescription ?? '',
                    aiResult: p,
                  ),
                ),
              ),
              child: ProofThumbnail(
                url: p.imageUrl,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(AppRadius.tile),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  p.taskDescription ?? 'Task',
                  style: AppText.cardHeader(size: 17),
                ),
              ),
              DfStatusPill(
                p.isApproved
                    ? 'Approved'
                    : p.isRejected
                    ? 'Rejected'
                    : 'Pending',
                tone: parentTone,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // AI decision + confidence + reason panel (info tone).
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(AppRadius.tile),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.sparkles,
                      size: 16,
                      color: AppColors.infoFg,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        confidence != null
                            ? '$verdict · AI confidence · '
                                  '${(confidence * 100).round()}%'
                            : verdict,
                        style: AppText.bodySecondary(
                          size: 13,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                if (p.aiReason != null && p.aiReason!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(p.aiReason!, style: AppText.bodySecondary(size: 12.5)),
                ],
              ],
            ),
          ),
          if (p.parentNote != null && p.parentNote!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.greenTint,
                borderRadius: BorderRadius.circular(AppRadius.tile),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    LucideIcons.messageSquare,
                    size: 14,
                    color: AppColors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.parentNote!,
                      style: AppText.bodySecondary(size: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String label, bool Function(HomeworkSession)? predicate) {
    final isSelected = _statusFilter == predicate;
    return DfChip(
      label,
      selected: isSelected,
      onTap: () {
        _statusFilter = predicate;
        _applyFilters();
      },
    );
  }

  /// Subject filter chip. null = no filter (show all).
  Widget _subjectChip(String label, String? value) {
    final isSelected = _subjectFilter == value;
    return DfChip(
      label,
      selected: isSelected,
      onTap: () {
        _subjectFilter = value;
        _applyFilters();
      },
    );
  }
}
