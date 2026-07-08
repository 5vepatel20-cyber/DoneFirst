class HomeworkSession {
  final String id;
  final String childId;
  final String parentId;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int minLockMinutes;
  final int? maxLiftMinutes;
  final String approvalMode;

  const HomeworkSession({
    required this.id,
    required this.childId,
    required this.parentId,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.minLockMinutes,
    this.maxLiftMinutes,
    this.approvalMode = 'balanced',
  });

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  factory HomeworkSession.fromMap(Map<String, dynamic> map) => HomeworkSession(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        parentId: map['parent_id'] as String,
        status: map['status'] as String? ?? 'active',
        startedAt: DateTime.parse(map['started_at'] as String),
        endedAt: map['ended_at'] != null ? DateTime.tryParse(map['ended_at'] as String) : null,
        minLockMinutes: map['min_lock_minutes'] as int? ?? 60,
        maxLiftMinutes: map['max_lift_minutes'] as int?,
        approvalMode: map['approval_mode'] as String? ?? 'balanced',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'child_id': childId,
        'parent_id': parentId,
        'status': status,
        'started_at': startedAt.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
        'min_lock_minutes': minLockMinutes,
        if (maxLiftMinutes != null) 'max_lift_minutes': maxLiftMinutes,
        'approval_mode': approvalMode,
      };
}
