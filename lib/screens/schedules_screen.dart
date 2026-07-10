import 'package:flutter/material.dart';
import '../services/schedule_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import 'lock_config_screen.dart';
import '../models/models.dart';

const List<String> weekdayNames = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

class SchedulesScreen extends StatefulWidget {
  final String childId;
  final String childName;
  const SchedulesScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  final _scheduleService = ScheduleService();
  final _sessionService = SessionService();
  List<RecurringSchedule> _schedules = [];
  bool _loading = true;
  String? _activeSessionId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final schedules = await _scheduleService.getSchedules(widget.childId);
    final active = await _sessionService.getActiveSession(widget.childId);
    if (mounted)
      setState(() {
        _schedules = schedules;
        _activeSessionId = active?.id;
        _loading = false;
      });
  }

  /// Shared dialog for both add and edit. Returns null on cancel.
  /// When [allowPickDay] is false the day-of-week row is hidden (edit
  /// mode), so the parent can't accidentally change the day. When
  /// [initialDuration] / [initialApprovalMode] are supplied they
  /// pre-fill the segmented buttons; otherwise the defaults match
  /// the add flow.
  static Future<({int dayOfWeek, int durationMinutes, String approvalMode})?>
      _showScheduleDialog({
    required BuildContext context,
    required String title,
    int? initialDay,
    int? initialDuration,
    String? initialApprovalMode,
    bool allowPickDay = true,
  }) async {
    int? selectedDay = initialDay;
    int duration = initialDuration ?? 60;
    String approvalMode = initialApprovalMode ?? 'balanced';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (allowPickDay) ...[
                  const Text(
                    'Day of Week',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: List.generate(
                      7,
                      (i) => ChoiceChip(
                        label: Text(weekdayNames[i]),
                        selected: selectedDay == i + 1,
                        onSelected: (v) => setDState(
                          () => selectedDay = v ? i + 1 : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Duration',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 30, label: Text('30m')),
                    ButtonSegment(value: 60, label: Text('1h')),
                    ButtonSegment(value: 90, label: Text('1.5h')),
                    ButtonSegment(value: 120, label: Text('2h')),
                  ],
                  selected: {duration},
                  onSelectionChanged: (v) =>
                      setDState(() => duration = v.first),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Approval',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'balanced', label: Text('Balanced')),
                    ButtonSegment(value: 'strict', label: Text('Strict')),
                  ],
                  selected: {approvalMode},
                  onSelectionChanged: (v) =>
                      setDState(() => approvalMode = v.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(allowPickDay ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return null;
    // Edit mode guarantees selectedDay stays at initialDay; add mode
    // requires a chosen day.
    final day = allowPickDay ? selectedDay : initialDay;
    if (day == null) return null;
    return (
      dayOfWeek: day,
      durationMinutes: duration,
      approvalMode: approvalMode,
    );
  }

  Future<void> _add() async {
    final result = await _showScheduleDialog(
      context: context,
      title: 'Add Recurring Schedule',
    );
    if (result != null) {
      await _scheduleService.addSchedule(
        childId: widget.childId,
        dayOfWeek: result.dayOfWeek,
        durationMinutes: result.durationMinutes,
        approvalMode: result.approvalMode,
      );
      await _load();
    }
  }

  Future<void> _edit(RecurringSchedule s) async {
    // Only duration + approval mode are mutable — the day of week
    // would require a delete-and-recreate (the service's
    // updateSchedule intentionally doesn't accept dayOfWeek because
    // for a weekly schedule "wrong day" almost always means "I meant
    // to add a different one", which is better expressed by adding).
    final result = await _showScheduleDialog(
      context: context,
      title: 'Edit Schedule (${s.dayName})',
      initialDuration: s.durationMinutes,
      initialApprovalMode: s.approvalMode,
      allowPickDay: false,
    );
    if (result != null) {
      await _scheduleService.updateSchedule(
        s.id,
        durationMinutes: result.durationMinutes,
        approvalMode: result.approvalMode,
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName}\'s Schedule'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _add)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _schedules.isEmpty
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
                      Icons.calendar_month,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No recurring schedule',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Add weekly homework routines',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Schedule'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _schedules.length,
              itemBuilder: (ctx, i) {
                final s = _schedules[i];
                final day = s.dayOfWeek;
                final dur = s.durationMinutes;
                final mode = s.approvalMode;
                final isToday = day == DateTime.now().weekday;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            (isToday
                                    ? AppColors.primary
                                    : AppColors.textSecondary)
                                .withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.calendar_today,
                        color: isToday
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    title: Text(
                      weekdayNames[day - 1],
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isToday
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text('$dur min | $mode'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isToday && _activeSessionId == null)
                          FilledButton.tonal(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LockConfigScreen(
                                  childId: widget.childId,
                                  childName: widget.childName,
                                ),
                              ),
                            ),
                            child: const Text('Start Now'),
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Edit schedule',
                          onPressed: () => _edit(s),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: AppColors.danger,
                          ),
                          tooltip: 'Delete schedule',
                          onPressed: () async {
                            await _scheduleService.deleteSchedule(s.id);
                            await _load();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
