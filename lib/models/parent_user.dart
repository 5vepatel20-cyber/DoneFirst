class ParentUser {
  final String id;
  final String email;
  final String displayName;
  final String? familyId;
  final String? role;

  const ParentUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.familyId,
    this.role,
  });

  factory ParentUser.fromMap(Map<String, dynamic> map) => ParentUser(
        id: map['id'] as String,
        email: map['email'] as String? ?? '',
        displayName: map['display_name'] as String? ?? '',
        familyId: map['family_id'] as String?,
        role: map['role'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        if (familyId != null) 'family_id': familyId,
        if (role != null) 'role': role,
      };
}
