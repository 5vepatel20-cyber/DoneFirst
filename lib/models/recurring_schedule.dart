class RecurringSchedule {
  final String id;
  final String childId;

  /// Weekday using Dart's own convention: [DateTime.monday] == 1
  /// through [DateTime.sunday] == 7.
  ///
  /// This matches what the day picker in SchedulesScreen has always
  /// written (`selectedDay = i + 1`) and what `DateTime.now().weekday`
  /// returns, so "is this schedule today?" is a plain equality with no
  /// off-by-one adjustment anywhere. Readers that subtracted 1 to
  /// index a Mon-first name list were reading every schedule as the
  /// day before the one the parent picked — the delete confirmation
  /// asked a parent to type "Thu" to remove the schedule the list card
  /// called "Wed", `getTodaySchedules` matched yesterday's rows, and
  /// day 7 (Sunday) was never returned at all because the query asked
  /// for 6.
  final int dayOfWeek;
  final int durationMinutes;
  final String approvalMode;

  const RecurringSchedule({
    required this.id,
    required this.childId,
    required this.dayOfWeek,
    this.durationMinutes = 60,
    this.approvalMode = 'balanced',
  });

  String get dayName {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return dayOfWeek >= DateTime.monday && dayOfWeek <= DateTime.sunday
        ? days[dayOfWeek - 1]
        : '?';
  }

  bool get isToday => dayOfWeek == DateTime.now().weekday;

  factory RecurringSchedule.fromMap(Map<String, dynamic> map) =>
      RecurringSchedule(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        dayOfWeek: map['day_of_week'] as int? ?? 0,
        durationMinutes: map['duration_minutes'] as int? ?? 60,
        approvalMode: map['approval_mode'] as String? ?? 'balanced',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'child_id': childId,
        'day_of_week': dayOfWeek,
        'duration_minutes': durationMinutes,
        'approval_mode': approvalMode,
      };
}
