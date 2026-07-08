class Family {
  final String id;
  final String name;

  const Family({required this.id, required this.name});

  factory Family.fromMap(Map<String, dynamic> map) => Family(
        id: map['id'] as String,
        name: map['name'] as String? ?? 'My Family',
      );

  Map<String, dynamic> toMap() => {'id': id, 'name': name};
}
