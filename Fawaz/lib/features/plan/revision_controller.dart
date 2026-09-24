import 'package:flutter/material.dart';
import 'package:omnia_ui/features/study/domain/revision_item.dart';
import 'package:omnia_ui/features/study/domain/study_repository.dart';

/// One planned study block and its sub-tasks (the subject's backlog and
/// revision topics). Every change is saved through the API; a failed save
/// puts the checkbox back and reports false.
class RevisionController extends ChangeNotifier {
  RevisionController({
    required StudyRepository repository,
    required this.title,
    required this.minutes,
    required this.start,
    this.subjectId,
    this.subjectName,
    this.reason,
  }) : _repository = repository;

  final StudyRepository _repository;
  final String title, start;
  final String? subjectId, subjectName, reason;
  final int minutes;

  List<RevisionItem> _items = const [];
  bool _loaded = false, _loading = false, _saving = false, _disposed = false;
  Object? _error;
  String? _loggedSessionId;

  bool get loaded => _loaded;
  bool get loading => _loading;
  bool get saving => _saving;
  Object? get error => _error;
  bool get sessionLogged => _loggedSessionId != null;

  List<String> get tasks => [for (final item in _items) item.title];
  bool isChecked(int index) => _items[index].completed;
  int get done => _items.where((item) => item.completed).length;

  Future<void> load() async {
    final subject = subjectId;
    if (subject == null) {
      _loaded = true;
      _notify();
      return;
    }
    _loading = true;
    _error = null;
    _notify();
    try {
      _items = await _repository.getTopics(subjectId: subject);
      _loaded = true;
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<bool> setChecked(int index, bool value) async {
    final item = _items[index];
    _replace(item.copyWith(completed: value));
    try {
      _replace(await _repository.setTopicDone(item.id, value));
      return true;
    } catch (_) {
      _replace(item);
      return false;
    }
  }

  /// Mark done: log the session's time and complete every topic.
  /// Undo: remove that logged session and reopen the topics.
  Future<bool> markAll(bool value) async {
    if (_saving) return false;
    _saving = true;
    _notify();
    try {
      if (value && _loggedSessionId == null) {
        final log = await _repository.logSession(minutes: minutes, subjectId: subjectId);
        _loggedSessionId = log.id;
      } else if (!value && _loggedSessionId != null) {
        await _repository.deleteSession(_loggedSessionId!);
        _loggedSessionId = null;
      }
      for (final item in [..._items]) {
        if (item.completed != value) {
          _replace(await _repository.setTopicDone(item.id, value));
        }
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _saving = false;
      _notify();
    }
  }

  /// Reopen every topic without touching logged time.
  Future<bool> resetTopics() async {
    try {
      for (final item in [..._items]) {
        if (item.completed) _replace(await _repository.setTopicDone(item.id, false));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> addTopic(String topic) async {
    final subject = subjectId;
    if (subject == null || topic.trim().isEmpty) return false;
    try {
      final created = await _repository.createTopic(subjectId: subject, title: topic, revision: true);
      _items = [..._items, created];
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _replace(RevisionItem item) {
    _items = [for (final i in _items) i.id == item.id ? item : i];
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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
