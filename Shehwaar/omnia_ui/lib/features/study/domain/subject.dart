class Subject {
  const Subject({required this.id, required this.name, this.description});
  final String id, name;
  final String? description;

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
    id: json['id'] as String, name: json['name'] as String,
    description: json['description'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'description': description,
  };
}
