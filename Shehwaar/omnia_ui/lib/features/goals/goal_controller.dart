import 'package:flutter/widgets.dart';
import 'package:omnia_ui/features/goals/domain/goal.dart';
import 'package:omnia_ui/features/goals/domain/goal_repository.dart';

/// App-owned goal state shared by Home and the Goals screen. The repository
/// is the source of truth; this mirrors it and applies the entities returned
/// by each successful operation.
// ponytail: same shape as TaskController; extract a shared base if a third
// feature needs it.
class GoalController extends ChangeNotifier {
  GoalController(this._repository);
  final GoalRepository _repository;

  List<Goal> _goals = const [];
  bool _loading = false, _loaded = false, _disposed = false;
  Object? _loadError;
  final _busy = <String>{};

  /// Soonest deadline first (undated last), then in the repository's order.
  List<Goal> get active => _sorted(_goals.where((goal) => !goal.completed));
  List<Goal> get completed => _sorted(_goals.where((goal) => goal.completed));
  bool get loading => _loading;
  bool get loaded => _loaded;
  Object? get loadError => _loadError;
  bool get isEmpty => _goals.isEmpty;
  bool isBusy(String id) => _busy.contains(id);

  static List<Goal> _sorted(Iterable<Goal> goals) {
    // Index tiebreak keeps the sort stable.
    final indexed = goals.indexed.toList()
      ..sort((a, b) {
        final ad = a.$2.deadline, bd = b.$2.deadline;
        if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
        if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
        return a.$1.compareTo(b.$1);
      });
    return [for (final (_, goal) in indexed) goal];
  }

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _loadError = null;
    _notify();
    try {
      _goals = await _repository.getGoals();
      _loaded = true;
    } catch (error) {
      _loadError = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Mutations return false on failure; state is left as the repository had it.
  Future<bool> create(Goal goal) => _run(null, () async {
    final created = await _repository.createGoal(goal);
    _goals = [..._goals, created];
  });

  Future<bool> update(Goal goal) => _run(goal.id, () async {
    _replace(await _repository.updateGoal(goal));
  });

  Future<bool> setCompleted(String id, bool completed) => _run(id, () async {
    _replace(await _repository.setCompleted(id, completed));
  });

  /// Records a measurable goal's real amount (e.g. 22.5 kg); fails for
  /// completion-only goals and negative values. Later, other modules
  /// (study, workouts, activity) can report through here.
  Future<bool> setCurrentValue(String id, double value) => _run(id, () async {
    final goal = _goals.firstWhere((goal) => goal.id == id);
    if (!goal.measurable) throw StateError('$id is completion-only');
    _replace(await _repository.updateGoal(goal.copyWith(currentValue: value)));
  });

  Future<bool> delete(String id) => _run(id, () async {
    await _repository.deleteGoal(id);
    _goals = [..._goals.where((goal) => goal.id != id)];
  });

  void _replace(Goal goal) =>
      _goals = [for (final g in _goals) g.id == goal.id ? goal : g];

  /// Ignores a second operation on a goal that already has one in flight.
  Future<bool> _run(String? id, Future<void> Function() operation) async {
    if (id != null && !_busy.add(id)) return false;
    _notify();
    try {
      await operation();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (id != null) _busy.remove(id);
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

class GoalScope extends InheritedNotifier<GoalController> {
  const GoalScope({
    super.key,
    required GoalController controller,
    required super.child,
  }) : super(notifier: controller);

  static GoalController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GoalScope>()!.notifier!;
}
