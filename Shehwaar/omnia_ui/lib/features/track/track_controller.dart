import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/track/domain/track_repository.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';

enum TrackSave {
  /// Another change was already in flight; nothing was sent.
  ignored,

  /// Stored, and Home and Track now show it.
  saved,

  /// Stored, but the dashboard couldn't reload; Home shows the old figures.
  savedNotRefreshed,
}

/// Logs one user's activity and sleep. It keeps no copy of the figures: the
/// dashboard stays their only owner and reloads after every stored change.
class TrackController extends ChangeNotifier {
  TrackController(this._repository, this._dashboard);
  final TrackRepository _repository;
  final DashboardController _dashboard;
  bool _busy = false, _disposed = false;

  /// A change is being stored or the dashboard is reloading after one.
  bool get busy => _busy;

  Future<ActivityDay> activity(DateTime day) => _repository.getActivity(day);
  Future<SleepEntry?> sleep(DateTime day) => _repository.getSleep(day);

  /// These throw [ApiException] when the change is refused, leaving the
  /// stored day and the dashboard as they were.
  Future<TrackSave> saveActivity(ActivityDay activity) =>
      _change(() => _repository.saveActivity(activity.normalized()));

  Future<TrackSave> saveSleep(SleepEntry entry) =>
      _change(() => _repository.saveSleep(entry));

  Future<TrackSave> deleteSleep(DateTime day) => _change(() async {
    try {
      await _repository.deleteSleep(day);
    } on ApiException catch (error) {
      if (!error.isNotFound) rethrow; // already gone: the outcome stands
    }
  });

  Future<TrackSave> _change(Future<void> Function() change) async {
    if (_busy) return TrackSave.ignored;
    _busy = true;
    _notify();
    try {
      await change();
      await _dashboard.load();
      return _dashboard.loadError == null
          ? TrackSave.saved
          : TrackSave.savedNotRefreshed;
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

class TrackScope extends InheritedNotifier<TrackController> {
  const TrackScope({
    super.key,
    required TrackController controller,
    required super.child,
  }) : super(notifier: controller);

  static TrackController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TrackScope>()!.notifier!;

  /// Read without subscribing (for callbacks).
  static TrackController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TrackScope>()!.notifier!;
}

/// What a finished log screen tells the user.
String savedMessage(String what, TrackSave result) =>
    result == TrackSave.savedNotRefreshed
    ? "$what, but Home couldn't refresh. Pull down on Home to try again."
    : '$what.';

/// Shown when a log screen is opened before today has loaded.
const notLoadedMessage =
    "Today hasn't loaded yet. Pull down on Home to try again.";
