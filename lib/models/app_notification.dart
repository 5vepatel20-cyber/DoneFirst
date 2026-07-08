class AppNotification {
  final String id;
  final String parentId;
  final String? childId;
  final String type;
  final String title;
  final String? body;
  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.parentId,
    this.childId,
    required this.type,
    required this.title,
    this.body,
    this.read = false,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
        id: map['id'] as String,
        parentId: map['parent_id'] as String,
        childId: map['child_id'] as String?,
        type: map['type'] as String,
        title: map['title'] as String,
        body: map['body'] as String?,
        read: map['read'] as bool? ?? false,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'parent_id': parentId,
        if (childId != null) 'child_id': childId,
        'type': type,
        'title': title,
        if (body != null) 'body': body,
        'read': read,
      };
}
