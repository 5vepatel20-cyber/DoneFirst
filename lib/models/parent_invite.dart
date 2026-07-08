class ParentInvite {
  final String id;
  final String familyId;
  final String inviterId;
  final String inviteeEmail;
  final String status;
  final DateTime createdAt;

  const ParentInvite({
    required this.id,
    required this.familyId,
    required this.inviterId,
    required this.inviteeEmail,
    this.status = 'pending',
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';

  factory ParentInvite.fromMap(Map<String, dynamic> map) => ParentInvite(
        id: map['id'] as String,
        familyId: map['family_id'] as String,
        inviterId: map['inviter_id'] as String,
        inviteeEmail: map['invitee_email'] as String,
        status: map['status'] as String? ?? 'pending',
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'family_id': familyId,
        'inviter_id': inviterId,
        'invitee_email': inviteeEmail,
        'status': status,
      };
}
