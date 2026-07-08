class Child {
  final String id;
  final String name;
  final String? familyId;
  final String? parentId;
  final String? color;
  final String? emoji;
  final int streakCount;
  final DateTime? lastStreakDate;

  const Child({
    required this.id,
    required this.name,
    this.familyId,
    this.parentId,
    this.color,
    this.emoji,
    this.streakCount = 0,
    this.lastStreakDate,
  });

  factory Child.fromMap(Map<String, dynamic> map) => Child(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        familyId: map['family_id'] as String?,
        parentId: map['parent_id'] as String?,
        color: map['color'] as String?,
        emoji: map['emoji'] as String?,
        streakCount: map['streak_count'] as int? ?? 0,
        lastStreakDate: map['last_streak_date'] != null
            ? DateTime.tryParse(map['last_streak_date'] as String)
            : null,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (familyId != null) 'family_id': familyId,
        if (parentId != null) 'parent_id': parentId,
        if (color != null) 'color': color,
        if (emoji != null) 'emoji': emoji,
        'streak_count': streakCount,
        if (lastStreakDate != null) 'last_streak_date': lastStreakDate!.toIso8601String(),
      };
}
