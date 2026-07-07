import 'package:flutter/material.dart';
import '../services/schedule_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import 'lock_config_screen.dart';

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
  List<Map<String, dynamic>> _schedules = [];
  bool _loading = true;
  int? _activeSessionId;

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
        _activeSessionId = active.isNotEmpty ? active.first['id'] : null;
        _loading = false;
      });
  }

  Future<void> _add() async {
    int? selectedDay;
    int duration = 60;
    String approvalMode = 'balanced';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text('Add Recurring Schedule'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Day of Week',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: List.generate(
                    7,
                    (i) => ChoiceChip(
                      label: Text(weekdayNames[i]),
                      selected: selectedDay == i + 1,
                      onSelected: (v) =>
                          setDState(() => selectedDay = v ? i + 1 : null),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedDay != null) {
      await _scheduleService.addSchedule(
        childId: widget.childId,
        dayOfWeek: selectedDay!,
        durationMinutes: duration,
        approvalMode: approvalMode,
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
                      color: AppColors.primary.withOpacity(0.08),
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
                final day = s['day_of_week'] as int? ?? 1;
                final dur = s['duration_minutes'] as int? ?? 60;
                final mode = s['approval_mode'] as String? ?? 'balanced';
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
                                .withOpacity(0.1),
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
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: AppColors.danger,
                          ),
                          onPressed: () async {
                            await _scheduleService.removeSchedule(s['id']);
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
