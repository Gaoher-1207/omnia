class Subject {
  const Subject({
    required this.id,
    required this.name,
    this.description,
    this.color,
  });
  final String id, name;
  final String? description;

  /// `#RRGGBB` chosen by the user, if any.
  final String? color;

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    color: json['color'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'color': color,
  };
}
