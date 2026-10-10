import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/plan/domain/plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/replan_proposal.dart';

/// Session-owned snapshots. Null selection means the server's current local day.
class PlanController extends ChangeNotifier {
  PlanController(this._repository, {this.loadsWithDashboard = false});
  final PlanRepository _repository;
  final bool loadsWithDashboard;
  DailyPlan? _plan;
  DailyPlan? _todayPlan;
  DateTime? _todayDate;
  bool _todayLoaded = false;
  DateTime? _selectedDate;
  Object? _error;
  bool _busy = false, _loaded = false, _disposed = false;
  ReplanProposal? _replanProposal;
  Object? _replanError;
  String? _replanNotice;
  bool _creatingProposal = false, _proposalActionBusy = false;
  int _request = 0;
  final _editedPlans = <String>{};
  DailyPlan? get plan => _plan;
  DailyPlan? get todayPlan => _todayPlan;
  DateTime? get todayDate => _todayDate;
  bool get todayLoaded => _todayLoaded;
  DateTime? get selectedDate => _selectedDate;
  Object? get error => _error;
  bool get busy => _busy;
  bool get loaded => _loaded;
  bool get mayBeStale => _editedPlans.contains(_plan?.id);
  ReplanProposal? get replanProposal => _replanProposal;
  Object? get replanError => _replanError;
  String? get replanNotice => _replanNotice;
  bool get creatingProposal => _creatingProposal;
  bool get proposalActionBusy => _proposalActionBusy;

  /// Create a backend-validated preview and reload its persisted representation.
  /// Neither call changes the active plan.
  Future<bool> createReplanProposal(String request) async {
    if (_disposed || _creatingProposal || _proposalActionBusy) return false;
    _creatingProposal = true;
    _replanError = null;
    _replanNotice = null;
    notifyListeners();
    try {
      final created = await _repository.createReplanProposal(
        request,
        date: _selectedDate,
      );
      final proposal = await _repository.getReplanProposal(created.id);
      if (_disposed) return false;
      _replanProposal = proposal;
      return true;
    } catch (failure) {
      if (!_disposed) _replanError = failure;
      return false;
    } finally {
      if (!_disposed) {
        _creatingProposal = false;
        notifyListeners();
      }
    }
  }

  Future<bool> loadReplanProposal(String proposalId) async {
    if (_disposed || _creatingProposal || _proposalActionBusy) return false;
    _creatingProposal = true;
    _replanError = null;
    notifyListeners();
    try {
      final proposal = await _repository.getReplanProposal(proposalId);
      if (_disposed) return false;
      _replanProposal = proposal;
      return true;
    } catch (failure) {
      if (!_disposed) _replanError = failure;
      return false;
    } finally {
      if (!_disposed) {
        _creatingProposal = false;
        notifyListeners();
      }
    }
  }

  Future<bool> applyReplanProposal() async {
    final proposal = _replanProposal;
    if (_disposed ||
        proposal == null ||
        !proposal.isPending ||
        _proposalActionBusy ||
        _creatingProposal) {
      return false;
    }
    _proposalActionBusy = true;
    _replanError = null;
    _replanNotice = null;
    notifyListeners();
    try {
      final updated = await _repository.applyReplanProposal(proposal.id);
      if (_disposed) return false;
      _setActivePlan(updated);
      _replanProposal = null;
      _replanNotice = 'Plan updated.';
      try {
        final refreshed = await _repository.getToday(date: _selectedDate);
        if (_disposed) return false;
        final active =
            refreshed != null && refreshed.revision >= updated.revision
            ? refreshed
            : updated;
        _setActivePlan(active);
      } catch (_) {
        if (!_disposed) {
          _replanNotice =
              'Plan updated. Pull to refresh if it looks out of date.';
        }
      }
      return true;
    } on ApiException catch (failure) {
      if (_disposed) return false;
      if (failure.code == 'replan_proposal_stale') {
        _replanProposal = null;
        _replanNotice = 'Your plan changed while this preview was open. Nothing was applied.';
        await _refreshAfterStaleProposal();
      } else if (failure.code == 'replan_proposal_expired') {
        // The backend has already retired this proposal; Apply cannot succeed.
        _replanProposal = null;
        _replanNotice = 'This preview expired. Nothing was changed.';
      } else if (failure.code == 'replan_invalid' ||
          failure.code == 'replan_proposal_conflict') {
        _replanProposal = null;
        _replanNotice =
            'This preview can no longer be applied. '
            'Nothing was changed.';
      } else {
        _replanError = failure;
      }
      return false;
    } catch (failure) {
      if (!_disposed) _replanError = failure;
      return false;
    } finally {
      if (!_disposed) {
        _proposalActionBusy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> dismissReplanProposal() async {
    final proposal = _replanProposal;
    if (_disposed ||
        proposal == null ||
        !proposal.isPending ||
        _proposalActionBusy ||
        _creatingProposal) {
      return false;
    }
    _proposalActionBusy = true;
    _replanError = null;
    _replanNotice = null;
    notifyListeners();
    try {
      await _repository.dismissReplanProposal(proposal.id);
      if (_disposed) return false;
      _replanProposal = null;
      return true;
    } on ApiException catch (failure) {
      if (_disposed) return false;
      // Already retired server-side; there is nothing left to dismiss.
      if (failure.code == 'replan_proposal_conflict') {
        _replanProposal = null;
        return true;
      }
      _replanError = failure;
      return false;
    } catch (failure) {
      if (!_disposed) _replanError = failure;
      return false;
    } finally {
      if (!_disposed) {
        _proposalActionBusy = false;
        notifyListeners();
      }
    }
  }

  void clearReplanNotice() {
    _replanNotice = null;
    if (!_disposed) notifyListeners();
  }

  void _setActivePlan(DailyPlan updated) {
    _plan = updated;
    _loaded = true;
    if (_selectedDate == null) {
      _todayPlan = updated;
      _todayDate = updated.date;
      _todayLoaded = true;
    }
  }

  Future<void> _refreshAfterStaleProposal() async {
    final request = ++_request;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final latest = await _repository.getToday(date: _selectedDate);
      if (!_disposed && request == _request) {
        _plan = latest;
        _loaded = true;
        if (_selectedDate == null) {
          _todayPlan = latest;
          _todayLoaded = true;
          if (latest != null) _todayDate = latest.date;
        }
      }
    } catch (failure) {
      if (!_disposed && request == _request) _error = failure;
    } finally {
      if (!_disposed && request == _request) _busy = false;
    }
  }

  void markEdited() {
    if (_plan != null) _editedPlans.add(_plan!.id);
    if (!_disposed) notifyListeners();
  }

  /// The dashboard already fetched today's persisted suggestion. Reuse that
  /// snapshot for Home and the initial Plan tab without a second request.
  void seedToday(DateTime date, DailyPlan? candidate) {
    if (_disposed) return;
    if (candidate != null &&
        (candidate.date.year != date.year ||
            candidate.date.month != date.month ||
            candidate.date.day != date.day)) {
      return;
    }
    final newDay =
        _todayDate == null ||
        _todayDate!.year != date.year ||
        _todayDate!.month != date.month ||
        _todayDate!.day != date.day;
    if (newDay) _todayPlan = null;
    _todayDate = date;
    // An earlier dashboard response can finish after explicit generation.
    final keepNewer =
        !newDay &&
        _todayPlan != null &&
        (candidate == null ||
            _todayPlan!.createdAt.isAfter(candidate.createdAt));
    if (!keepNewer) _todayPlan = candidate;
    _todayLoaded = true;
    if (_selectedDate == null && !_busy) {
      _plan = _todayPlan;
      _loaded = true;
      _error = null;
    }
    notifyListeners();
  }

  void seedTodayError(Object failure) {
    if (_disposed || _loaded || _busy || _selectedDate != null) return;
    _error = failure;
    notifyListeners();
  }

  Future<void> selectDate(DateTime? date) {
    _selectedDate = date;
    if (date == null && _todayLoaded) {
      ++_request;
      _busy = false;
      _plan = _todayPlan;
      _loaded = true;
      _error = null;
      notifyListeners();
      return Future.value();
    }
    _plan = null;
    _loaded = false;
    return _run(() => _repository.getToday(date: date), replace: true);
  }

  Future<void> load() => _run(() => _repository.getToday(date: _selectedDate));
  Future<void> generate() => _run(_repository.generate);

  Future<void> _run(
    Future<DailyPlan?> Function() operation, {
    bool replace = false,
  }) async {
    if (_disposed || (_busy && !replace)) return;
    final request = ++_request;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await operation();
      if (!_disposed && request == _request) {
        _plan = result;
        _loaded = true;
        if (_selectedDate == null) {
          _todayPlan = result;
          _todayLoaded = true;
          if (result != null) _todayDate = result.date;
        }
      }
    } catch (failure) {
      if (!_disposed && request == _request) _error = failure;
    } finally {
      if (!_disposed && request == _request) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PlanScope extends InheritedNotifier<PlanController> {
  const PlanScope({
    super.key,
    required PlanController controller,
    required super.child,
  }) : super(notifier: controller);
  static PlanController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlanScope>()!.notifier!;
  static PlanController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlanScope>()?.notifier;
}
