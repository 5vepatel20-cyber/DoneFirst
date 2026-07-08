import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/session_service.dart';
import '../services/proof_service.dart';
import '../theme/app_theme.dart';
import '../widgets/error_banner.dart';
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
      filtered = filtered
          .where((s) => s.status.toLowerCase().contains(query))
          .toList();
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
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
        actions: [
          if (_dateRange != null || _searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
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
                            hintText: 'Search by status...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
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
                        icon: const Icon(Icons.date_range, size: 18),
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
                                  Icons.history,
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
                                        ? Icons.check_circle
                                        : Icons.play_circle,
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
                                subtitle: Text(
                                  'Min: ${s.minLockMinutes}m | ${s.approvalMode}',
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
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
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                ),
                                child: Image.network(
                                  p.imageUrl,
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
                                          Icons.comment,
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
}
