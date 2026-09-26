import 'package:flutter/material.dart';
import 'package:omnia_ui/features/study/domain/revision_repository.dart';
import 'package:omnia_ui/features/study/domain/study_session.dart';

/// App-owned state for one study session, retained across route changes.
/// Updates are applied locally first, then persisted; a failed save reverts.
class RevisionController extends ChangeNotifier {
  RevisionController({
    required this._session,
    required this._repository,
  });

  StudySession _session;
  final RevisionRepository _repository;

  StudySession get session => _session;
  String get title => _session.title;
  List<String> get tasks => [
    for (final item in _session.revisionItems) item.title,
  ];
  bool isChecked(int index) => _session.revisionItems[index].completed;
  int get done => _session.revisionItems.where((item) => item.completed).length;

  void setChecked(int index, bool value) => _save(
    _session.copyWith(
      revisionItems: [
        for (final (i, item) in _session.revisionItems.indexed)
          i == index ? item.copyWith(completed: value) : item,
      ],
    ),
  );

  void markAll(bool value) => _save(
    _session.copyWith(
      revisionItems: [
        for (final item in _session.revisionItems)
          item.copyWith(completed: value),
      ],
    ),
  );

  void rename(String value) {
    if (value.trim().isEmpty) return;
    _save(_session.copyWith(title: value.trim()));
  }

  Future<void> _save(StudySession next) async {
    final previous = _session;
    _session = next;
    notifyListeners();
    // Only apply the result if no newer edit replaced this one meanwhile.
    try {
      final saved = await _repository.updateSession(next);
      if (identical(_session, next)) _session = saved;
    } catch (_) {
      if (identical(_session, next)) _session = previous;
      rethrow;
    } finally {
      notifyListeners();
    }
  }
}

class RevisionScope extends InheritedNotifier<RevisionController> {
  const RevisionScope({
    super.key,
    required RevisionController controller,
    required super.child,
  }) : super(notifier: controller);

  static RevisionController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RevisionScope>()!.notifier!;
}
