/// A sub-task embedded in a study session, not a second standalone task system.
class RevisionItem {
  const RevisionItem({required this.id, required this.title, this.completed = false});
  final String id, title;
  final bool completed;

  factory RevisionItem.fromJson(Map<String, dynamic> json) => RevisionItem(
    id: json['id'] as String, title: json['title'] as String,
    completed: json['completed'] as bool? ?? false,
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'completed': completed,
  };
  RevisionItem copyWith({String? title, bool? completed}) => RevisionItem(
    id: id, title: title ?? this.title, completed: completed ?? this.completed,
  );
}
