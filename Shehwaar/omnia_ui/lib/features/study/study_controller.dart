import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/study_repository.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';

/// One user's subjects and upcoming exams, shared by every Study screen.
/// The repository is the source of truth: after each change both lists are
/// read back from it, and the dashboard (Today's next exam) reloads.
class StudyController extends ChangeNotifier {
  StudyController(this._repository, this._dashboard);
  final StudyRepository _repository;
  final DashboardController _dashboard;

  List<Subject> _subjects = const [];
  List<Exam> _exams = const [];
  bool _loading = false, _loaded = false, _busy = false, _disposed = false;
  Object? _loadError;

  /// By name.
  List<Subject> get subjects => _subjects;

  /// Upcoming, nearest first.
  List<Exam> get exams => _exams;
  bool get loading => _loading;

  /// True once the lists have loaded at least once; a later failed reload
  /// keeps them.
  bool get loaded => _loaded;
  Object? get loadError => _loadError;

  /// A change is being stored.
  bool get busy => _busy;

  Subject? subject(String id) =>
      _subjects.where((subject) => subject.id == id).firstOrNull;
  Exam? exam(String id) => _exams.where((exam) => exam.id == id).firstOrNull;
  List<Exam> examsFor(String subjectId) => [
    for (final exam in _exams)
      if (exam.subjectId == subjectId) exam,
  ];

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _loadError = null;
    _notify();
    try {
      final (subjects, exams) = await (
        _repository.getSubjects(),
        _repository.getExams(),
      ).wait;
      _subjects = subjects;
      _exams = exams;
      _loaded = true;
    } on ParallelWaitError<dynamic, dynamic> catch (error) {
      _loadError = error.errors.$1?.error ?? error.errors.$2?.error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  // Each change returns what the server stored, or null when another change
  // was already in flight. A refusal throws [ApiException] and leaves the
  // lists as they were, so a form can show it and keep its input.

  Future<Subject?> createSubject(String name) =>
      _change(() => _repository.createSubject(name), examsChanged: false);

  Future<Subject?> renameSubject(String id, String name) =>
      _change(() => _repository.renameSubject(id, name));

  /// Also removes its exams.
  Future<bool?> deleteSubject(String id) =>
      _change(() => _gone(_repository.deleteSubject(id)));

  Future<Exam?> createExam(ExamDraft draft) =>
      _change(() => _repository.createExam(draft));

  Future<Exam?> updateExam(String id, ExamDraft draft) =>
      _change(() => _repository.updateExam(id, draft));

  Future<bool?> deleteExam(String id) =>
      _change(() => _gone(_repository.deleteExam(id)));

  /// Already deleted elsewhere counts as deleted.
  static Future<bool> _gone(Future<void> delete) async {
    try {
      await delete;
    } on ApiException catch (error) {
      if (!error.isNotFound) rethrow;
    }
    return true;
  }

  Future<T?> _change<T>(
    Future<T> Function() change, {
    bool examsChanged = true,
  }) async {
    if (_busy) return null;
    _busy = true;
    _notify();
    try {
      final result = await change();
      await load();
      // A renamed subject, or any exam change, can move Today's next exam.
      if (examsChanged) await _dashboard.load();
      return result;
    } finally {
      _busy = false;
      _notify();
    }
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

class StudyScope extends InheritedNotifier<StudyController> {
  const StudyScope({
    super.key,
    required StudyController controller,
    required super.child,
  }) : super(notifier: controller);

  static StudyController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudyScope>()!.notifier!;

  /// Read without subscribing (for callbacks).
  static StudyController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StudyScope>()!.notifier!;
}
