import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/schedule_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/destructive_confirm_dialog.dart';
import '../widgets/df_kit.dart';
import 'lock_config_screen.dart';
import '../models/models.dart';

const List<String> weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
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
  String? _error;
  String? _activeSessionId;

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
      // Schedules + the active session lookup are independent reads.
      // The "Start now" button on each schedule row depends on
      // _activeSessionId being set, but the two reads themselves
      // don't depend on each other — fire them in parallel.
      final results = await Future.wait<Object?>([
        _scheduleService.getSchedules(widget.childId),
        _sessionService.getActiveSession(widget.childId),
      ]);
      final schedules = results[0] as List;
      final active = results[1] as HomeworkSession?;
      if (mounted) {
        setState(() {
          _schedules = schedules.cast();
          _activeSessionId = active?.id;
          _loading = false;
        });
      }
    } catch (e) {
      // Without this catch, a transient RLS hiccup on either read
      // would leave _loading = true forever (the setState above
      // is the only place it flips false) and the spinner would
      // spin until the parent gives up.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
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
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          title: Text(title, style: AppText.cardHeader(size: 18)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (allowPickDay) ...[
                  DfSectionLabel('Day of week'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      7,
                      (i) => DfChip(
                        weekdayNames[i],
                        selected: selectedDay == i + 1,
                        onTap: () => setDState(
                          () => selectedDay = (selectedDay == i + 1)
                              ? null
                              : i + 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                DfSectionLabel('Duration'),
                DfSegmented<int>(
                  options: const [
                    (value: 30, label: '30m'),
                    (value: 60, label: '1h'),
                    (value: 90, label: '1.5h'),
                    (value: 120, label: '2h'),
                  ],
                  selected: duration,
                  onChanged: (v) => setDState(() => duration = v),
                ),
                const SizedBox(height: 16),
                DfSectionLabel('Who approves'),
                DfSegmented<String>(
                  options: const [
                    (value: 'balanced', label: 'AI + you'),
                    (value: 'strict', label: 'You only'),
                  ],
                  selected: approvalMode,
                  onChanged: (v) => setDState(() => approvalMode = v),
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
      title: 'Add recurring schedule',
    );
    if (result != null) {
      try {
        await _scheduleService.addSchedule(
          childId: widget.childId,
          dayOfWeek: result.dayOfWeek,
          durationMinutes: result.durationMinutes,
          approvalMode: result.approvalMode,
        );
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn’t add schedule: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
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
      title: 'Edit ${s.dayName} schedule',
      initialDuration: s.durationMinutes,
      initialApprovalMode: s.approvalMode,
      allowPickDay: false,
    );
    if (result != null) {
      try {
        await _scheduleService.updateSchedule(
          s.id,
          durationMinutes: result.durationMinutes,
          approvalMode: result.approvalMode,
        );
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn’t update schedule: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  /// Confirm-then-delete for a recurring schedule. Previously this
  /// was a single-tap IconButton — a stray double-tap could erase a
  /// weekly schedule with no warning. Now the parent must type the
  /// schedule's short identifier (e.g. "Mon (1h)") to confirm.
  Future<void> _confirmDelete(RecurringSchedule s) async {
    final phrase = '${s.dayName} (${_friendlyDuration(s.durationMinutes)})';
    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: 'Delete ${widget.childName}\'s ${s.dayName} schedule?',
      description:
          'This will stop automatically starting ${s.dayName.toLowerCase()} '
          'homework sessions for ${widget.childName}. '
          'You can re-create it anytime.',
      confirmPhrase: phrase,
      confirmButtonLabel: 'Delete schedule',
      warningText:
          'Future ${s.dayName.toLowerCase()} sessions will need to be started '
          'manually until a new schedule is added.',
    );
    if (!confirmed) return;
    try {
      await _scheduleService.deleteSchedule(s.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn’t delete: $e')));
    }
  }

  /// "30m" / "1h" / "1.5h" / "2h" formatting for the confirm
  /// phrase + warning copy. Whole hours have no decimal; half-hours
  /// round to "1.5h" / "2.5h" only when the minutes line up exactly.
  String _friendlyDuration(int minutes) {
    if (minutes % 60 == 0) return '${minutes ~/ 60}h';
    final hours = minutes / 60;
    // Strip trailing .0 so 90m → "1.5h" not "1.5h", 30m → "30m".
    if (hours == hours.roundToDouble()) {
      return '${hours.toInt()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }

  String _approvalLabel(String mode) =>
      mode == 'strict' ? 'You only' : 'AI + you';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName}\'s schedule'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Add schedule',
            onPressed: _add,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError(_error!);
    if (_schedules.isEmpty) {
      return DfEmptyState(
        icon: LucideIcons.calendarDays,
        title: 'No recurring schedule',
        hint: 'Add a weekly homework routine so sessions start themselves.',
        ctaLabel: 'Add schedule',
        onCta: _add,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      itemCount: _schedules.length,
      itemBuilder: (ctx, i) {
        final s = _schedules[i];
        final isToday = s.dayOfWeek == DateTime.now().weekday;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DfCard(
            borderColor: isToday
                ? AppColors.green.withValues(alpha: 0.4)
                : AppColors.borderCol,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppColors.greenTint
                            : AppColors.border2,
                        borderRadius: BorderRadius.circular(AppRadius.iconTile),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        LucideIcons.calendarCheck,
                        size: 18,
                        color: isToday ? AppColors.green : AppColors.ink45,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            weekdayNames[s.dayOfWeek - 1],
                            style: AppText.cardHeader(size: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_friendlyDuration(s.durationMinutes)} · ${_approvalLabel(s.approvalMode)}',
                            style: AppText.caption(),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.pencil,
                        size: 18,
                        color: AppColors.ink45,
                      ),
                      tooltip: 'Edit schedule',
                      onPressed: () => _edit(s),
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.trash2,
                        size: 18,
                        color: AppColors.dangerFg,
                      ),
                      tooltip: 'Delete schedule',
                      onPressed: () => _confirmDelete(s),
                    ),
                  ],
                ),
                if (isToday && _activeSessionId == null) ...[
                  const SizedBox(height: 12),
                  DfButton.outline(
                    'Start now',
                    icon: LucideIcons.play,
                    expand: false,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LockConfigScreen(
                          childId: widget.childId,
                          childName: widget.childName,
                          // Pre-fill from this schedule so the
                          // parent doesn't re-pick duration and
                          // approval mode they already set on the
                          // schedule. Packs aren't part of the
                          // schedule today so they still default
                          // to empty.
                          initialMinLock: s.durationMinutes,
                          initialApprovalMode: s.approvalMode,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoading() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DfCard(
            color: AppColors.border2,
            borderColor: AppColors.border2,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.borderCol,
                    borderRadius: BorderRadius.circular(AppRadius.iconTile),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 100,
                        color: AppColors.borderCol,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 140,
                        color: AppColors.borderCol,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        const SizedBox(height: 60),
        DfCard(
          child: Column(
            children: [
              const Icon(
                LucideIcons.wifiOff,
                color: AppColors.dangerFg,
                size: 28,
              ),
              const SizedBox(height: 10),
              Text(
                'Couldn\'t load schedules',
                style: AppText.cardHeader(size: 16),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.body(size: 13),
              ),
              const SizedBox(height: 16),
              DfButton.outline(
                'Try again',
                icon: LucideIcons.refreshCw,
                onPressed: _load,
                expand: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
