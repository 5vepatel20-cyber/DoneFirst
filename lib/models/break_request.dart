class BreakRequest {
  final String id;
  final String sessionId;
  final String childId;
  final String status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  const BreakRequest({
    required this.id,
    required this.sessionId,
    required this.childId,
    this.status = 'pending',
    required this.createdAt,
    this.startedAt,
    this.endedAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isDenied => status == 'denied';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  /// True while the parent has approved this break and the timer
  /// hasn't been ended. Used by the kid app's realtime listener
  /// to release the lock for the duration of the break.
  bool get isActiveBreak => isApproved && startedAt != null && endedAt == null;

  factory BreakRequest.fromMap(Map<String, dynamic> map) => BreakRequest(
        id: map['id'] as String,
        sessionId: map['session_id'] as String,
        childId: map['child_id'] as String,
        status: map['status'] as String? ?? 'pending',
        createdAt: DateTime.parse(map['created_at'] as String),
        startedAt: map['started_at'] == null
            ? null
            : DateTime.tryParse(map['started_at'] as String),
        endedAt: map['ended_at'] == null
            ? null
            : DateTime.tryParse(map['ended_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'child_id': childId,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
      };
}
