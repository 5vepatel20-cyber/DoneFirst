import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
import '../utils/subjects.dart';
import '../widgets/error_banner.dart';
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
    setState(() { _loading = true; _error = null; });
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? RetryWidget(message: _error!, onRetry: _load)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search tasks, status, or approval mode...',
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
                          style: const TextStyle(fontSize: 14),
                          onChanged: (_) => _applyFilters(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _pickDateRange,
                        icon: const Icon(LucideIcons.calendar, size: 18),
                        label: Text(
                          _dateRange != null
                              ? '${_dateRange!.start.month}/${_dateRange!.start.day}'
                              : 'Filter',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Result count + status chip row. The chip row is
                // the only new filter — search and date range were
                // already there but the user had no way to scope to
                // "only completed" or "only in-progress".
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        _allSessions.isEmpty
                            ? ''
                            : 'Showing ${_filteredSessions.length} of '
                                '${_allSessions.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      _statusChip('All', null),
                      const SizedBox(width: 4),
                      _statusChip(
                        'Active',
                        (s) => !s.isCompleted,
                      ),
                      const SizedBox(width: 4),
                      _statusChip(
                        'Completed',
                        (s) => s.isCompleted,
                      ),
                    ],
                  ),
                ),
                // Subject filter row. Horizontally scrollable so the
                // chip list scales as we add more subjects without
                // overflowing on small screens.
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _subjectChip('All subjects', null),
                      ...kSubjects.map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: _subjectChip(s, s),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _filteredSessions.isEmpty
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
                                  LucideIcons.history,
                                  size: 48,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No sessions found',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Try adjusting your filters',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredSessions.length,
                          itemBuilder: (ctx, i) {
                            final s = _filteredSessions[i];
                            final date = s.startedAt.toIso8601String()
                                .substring(0, 10);
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
                                        : LucideIcons.playCircle,
                                    color: s.isCompleted
                                        ? AppColors.success
                                        : AppColors.accent,
                                  ),
                                ),
                                title: Text(
                                  '${s.status} — $date',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(
                                      'Min: ${s.minLockMinutes}m | '
                                      '${s.approvalMode}',
                                    ),
                                    // Show the subject set for this
                                    // session inline so parents can see
                                    // at a glance what the kid worked
                                    // on — also lets them mentally
                                    // validate the active subject
                                    // filter without opening it.
                                    if ((_sessionSubjects[s.id] ?? const {})
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                        ),
                                        child: Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: (_sessionSubjects[s.id]!)
                                              .map(
                                                (subj) => Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 6,
                                                    vertical: 1,
                                                  ),
                                                  decoration:
                                                      BoxDecoration(
                                                    color: AppColors.accent
                                                        .withValues(
                                                            alpha: 0.08),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      4,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    subj,
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color:
                                                          AppColors.accent,
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: const Icon(
                                  LucideIcons.chevronRight,
                                  size: 16,
                                ),
                                onTap: () => _showSessionProofs(s.id),
                              ),
                            );
                          },
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
          appBar: AppBar(title: const Text('Proofs')),
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
                                Row(
                                  children: [
                                    _smallBadge(
                                      'AI: ${p.aiDecision ?? "pending"}',
                                      p.aiDecision == 'approved'
                                          ? AppColors.success
                                          : p.aiDecision == 'rejected'
                                          ? AppColors.danger
                                          : AppColors.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    _smallBadge(
                                      'Parent: ${p.parentDecision}',
                                      p.isApproved
                                          ? AppColors.success
                                          : p.isRejected
                                          ? AppColors.danger
                                          : AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                                if (p.aiReason != null && p.aiReason!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      p.aiReason!,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                if (p.parentNote != null && p.parentNote!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          LucideIcons.messageSquare,
                                          size: 12,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            p.parentNote!,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
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
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }

  Widget _statusChip(
    String label,
    bool Function(HomeworkSession)? predicate,
  ) {
    final isSelected = _statusFilter == predicate;
    return InkWell(
      onTap: () {
        _statusFilter = predicate;
        _applyFilters();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Subject filter chip. null = no filter (show all). Visually
  /// identical to _statusChip but reads/writes a different state
  /// field; inlined here rather than parameterised because
  /// unifying them would force the status filter to use String
  /// state too and lose the predicate-based extensibility.
  Widget _subjectChip(String label, String? value) {
    final isSelected = _subjectFilter == value;
    return InkWell(
      onTap: () {
        _subjectFilter = value;
        _applyFilters();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          border: Border.all(
            color: isSelected
                ? AppColors.accent
                : AppColors.textSecondary.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
