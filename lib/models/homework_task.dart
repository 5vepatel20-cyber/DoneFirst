class HomeworkTask {
  final String id;
  final String sessionId;
  final String description;
  final String subject;
  final String status;

  const HomeworkTask({
    required this.id,
    required this.sessionId,
    required this.description,
    this.subject = 'General',
    this.status = 'pending',
  });

  bool get isPending => status == 'pending';
  bool get isSubmitted => status == 'submitted';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory HomeworkTask.fromMap(Map<String, dynamic> map) => HomeworkTask(
        id: map['id'] as String,
        sessionId: map['session_id'] as String,
        description: map['description'] as String? ?? '',
        subject: map['subject'] as String? ?? 'General',
        status: map['status'] as String? ?? 'pending',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'description': description,
        'subject': subject,
        'status': status,
      };
}
