class AiResult {
  final String decision;
  final double confidence;
  final String reason;

  const AiResult({
    required this.decision,
    required this.confidence,
    required this.reason,
  });

  bool get isApproved => decision == 'approved';
  bool get needsReview => decision == 'needs_review';
  bool get isRejected => decision == 'rejected';

  factory AiResult.fromJson(Map<String, dynamic> json) => AiResult(
        decision: json['decision'] as String? ?? 'needs_review',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        reason: json['reason'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'decision': decision,
        'confidence': confidence,
        'reason': reason,
      };
}

class ProofSubmission {
  final String id;
  final String taskId;
  final String? sessionId;
  final String imageUrl;
  final List<String> imageUrls;
  final String? optionalNote;
  final String? parentNote;
  final String? aiDecision;
  final double? aiConfidence;
  final String? aiReason;
  final String parentDecision;
  final DateTime createdAt;
  final DateTime? parentActedAt;
  String? taskDescription;

  ProofSubmission({
    required this.id,
    required this.taskId,
    this.sessionId,
    required this.imageUrl,
    this.imageUrls = const [],
    this.optionalNote,
    this.parentNote,
    this.aiDecision,
    this.aiConfidence,
    this.aiReason,
    this.parentDecision = 'pending',
    required this.createdAt,
    this.parentActedAt,
    this.taskDescription,
  });

  bool get isPending => parentDecision == 'pending';
  bool get isApproved => parentDecision == 'approved';
  bool get isRejected => parentDecision == 'rejected';
  bool get hasMultiplePhotos => imageUrls.length > 1;

  factory ProofSubmission.fromMap(Map<String, dynamic> map) => ProofSubmission(
        id: map['id'] as String,
        taskId: map['task_id'] as String,
        sessionId: map['session_id'] as String?,
        imageUrl: map['image_url'] as String? ?? '',
        imageUrls: (map['image_urls'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            (map['image_url'] != null ? [map['image_url'] as String] : []),
        optionalNote: map['optional_note'] as String?,
        parentNote: map['parent_note'] as String?,
        aiDecision: map['ai_decision'] as String?,
        aiConfidence: (map['ai_confidence'] as num?)?.toDouble(),
        aiReason: map['ai_reason'] as String?,
        parentDecision: map['parent_decision'] as String? ?? 'pending',
        createdAt: DateTime.parse(map['created_at'] as String),
        parentActedAt: map['parent_acted_at'] != null
            ? DateTime.tryParse(map['parent_acted_at'] as String)
            : null,
        taskDescription: map['task_description'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'task_id': taskId,
        if (sessionId != null) 'session_id': sessionId,
        'image_url': imageUrl,
        'image_urls': imageUrls,
        if (optionalNote != null) 'optional_note': optionalNote,
        if (parentNote != null) 'parent_note': parentNote,
        if (aiDecision != null) 'ai_decision': aiDecision,
        if (aiConfidence != null) 'ai_confidence': aiConfidence,
        if (aiReason != null) 'ai_reason': aiReason,
        'parent_decision': parentDecision,
        if (parentActedAt != null)
          'parent_acted_at': parentActedAt!.toIso8601String(),
      };
}
