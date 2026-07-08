class LockPreset {
  final String id;
  final String parentId;
  final String name;
  final int minLockMinutes;
  final int maxLiftMinutes;
  final String approvalMode;
  final List<String> selectedPacks;
  final DateTime createdAt;

  const LockPreset({
    required this.id,
    required this.parentId,
    required this.name,
    this.minLockMinutes = 60,
    this.maxLiftMinutes = 120,
    this.approvalMode = 'balanced',
    this.selectedPacks = const [],
    required this.createdAt,
  });

  factory LockPreset.fromMap(Map<String, dynamic> map) => LockPreset(
        id: map['id'] as String,
        parentId: map['parent_id'] as String,
        name: map['name'] as String? ?? '',
        minLockMinutes: map['min_lock_minutes'] as int? ?? 60,
        maxLiftMinutes: map['max_lift_minutes'] as int? ?? 120,
        approvalMode: map['approval_mode'] as String? ?? 'balanced',
        selectedPacks: (map['selected_packs'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'parent_id': parentId,
        'name': name,
        'min_lock_minutes': minLockMinutes,
        'max_lift_minutes': maxLiftMinutes,
        'approval_mode': approvalMode,
        'selected_packs': selectedPacks,
      };
}
