import 'package:omnia_ui/features/study/domain/revision_item.dart';

const _unchanged = Object();

class StudySession {
  StudySession({
    required this.id, required this.subjectId, required this.title,
    required this.startsAt, required this.duration, this.examId,
    List<RevisionItem> revisionItems = const [],
  }) : revisionItems = List.unmodifiable(revisionItems) {
    if (id.trim().isEmpty || subjectId.trim().isEmpty || title.trim().isEmpty) {
      throw ArgumentError('Session id, subjectId and title must not be empty.');
    }
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration');
    }
    if (this.revisionItems.map((item) => item.id).toSet().length != this.revisionItems.length) {
      throw ArgumentError('Revision item ids must be unique within a session.');
    }
  }

  final String id, subjectId, title;
  final String? examId;
  final DateTime startsAt;
  final Duration duration;
  final List<RevisionItem> revisionItems;

  factory StudySession.fromJson(Map<String, dynamic> json) => StudySession(
    id: json['id'] as String, subjectId: json['subjectId'] as String,
    examId: json['examId'] as String?, title: json['title'] as String,
    startsAt: DateTime.parse(json['startsAt'] as String),
    duration: Duration(seconds: json['durationSeconds'] as int),
    revisionItems: (json['revisionItems'] as List<dynamic>? ?? [])
        .map((item) => RevisionItem.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'subjectId': subjectId, 'examId': examId, 'title': title,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'durationSeconds': duration.inSeconds,
    'revisionItems': revisionItems.map((item) => item.toJson()).toList(),
  };
  StudySession copyWith({
    String? title, String? subjectId, Object? examId = _unchanged,
    DateTime? startsAt, Duration? duration, List<RevisionItem>? revisionItems,
  }) => StudySession(
    id: id, subjectId: subjectId ?? this.subjectId, title: title ?? this.title,
    examId: identical(examId, _unchanged) ? this.examId : examId as String?,
    startsAt: startsAt ?? this.startsAt, duration: duration ?? this.duration,
    revisionItems: revisionItems ?? this.revisionItems,
  );
}
