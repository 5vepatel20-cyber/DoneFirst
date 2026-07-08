class RecurringSchedule {
  final String id;
  final String childId;
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
    return dayOfWeek >= 0 && dayOfWeek < 7 ? days[dayOfWeek] : '?';
  }

  bool get isToday => dayOfWeek == DateTime.now().weekday - 1;

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
