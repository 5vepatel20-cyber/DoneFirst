class BreakRequest {
  final String id;
  final String sessionId;
  final String childId;
  final String status;
  final DateTime createdAt;

  const BreakRequest({
    required this.id,
    required this.sessionId,
    required this.childId,
    this.status = 'pending',
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isDenied => status == 'denied';

  factory BreakRequest.fromMap(Map<String, dynamic> map) => BreakRequest(
        id: map['id'] as String,
        sessionId: map['session_id'] as String,
        childId: map['child_id'] as String,
        status: map['status'] as String? ?? 'pending',
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'child_id': childId,
        'status': status,
      };
}
