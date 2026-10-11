import 'package:flutter/material.dart';
import 'package:omnia_ui/features/assistant/widgets/ask_omnia_button.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/choice_segments.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/select_field.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/insights/activity_insights.dart';
import 'package:omnia_ui/features/insights/widgets/habit_grid.dart';
import 'package:omnia_ui/features/study/domain/study_log.dart';
import 'package:omnia_ui/features/track/track_controller.dart';

/// Workout consistency and steps for this week or month, computed only from
/// days the user actually logged. A day that wasn't logged is shown and
/// counted as "not logged", never as zero.
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});
  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  InsightRange _range = InsightRange.week;
  DateTime? _today;
  TrackController? _track;
  bool _trackWasBusy = false;
  ActivityInsights? _insights;
  StudyInsights? _study;
  bool _studyFailed = false;
  Object? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final track = context
        .dependOnInheritedWidgetOfExactType<TrackScope>()
        ?.notifier;
    if (track != _track) {
      _track?.removeListener(_onTrack);
      _track = track?..addListener(_onTrack);
    }
    final today = DashboardScope.of(context).dashboard?.date;
    if (today != null && !_sameDay(today, _today)) {
      _today = today;
      _load();
    }
  }

  @override
  void dispose() {
    _track?.removeListener(_onTrack);
    super.dispose();
  }

  /// A log saved elsewhere (Today, Areas) shows up here without a manual refresh.
  void _onTrack() {
    final busy = _track!.busy;
    if (_trackWasBusy && !busy) _load();
    _trackWasBusy = busy;
  }

  static bool _sameDay(DateTime a, DateTime? b) =>
      b != null && a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _load() async {
    final today = _today;
    if (today == null) return;
    final request = ++_request;
    final span = insightSpan(_range, today);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Nothing after today can be logged, so it isn't requested.
      final to = span.to.isAfter(today) ? today : span.to;
      final dependencies = AppDependenciesScope.of(context);
      final studyLog = dependencies.study
          .getStudyLog(span.from, to)
          .then<List<StudyLog>?>((log) => log, onError: (_) => null);
      final history = await dependencies.track.activityHistory(span.from, to);
      final log = await studyLog;
      if (!mounted || request != _request) return;
      setState(() {
        _insights = ActivityInsights.from(
          history,
          from: span.from,
          to: span.to,
          today: today,
        );
        _studyFailed = log == null;
        _study = log == null
            ? null
            : StudyInsights.from(
                log,
                from: span.from,
                to: span.to,
                today: today,
              );
        _loading = false;
      });
    } catch (failure) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = failure;
        _loading = false;
      });
    }
  }

  void _select(InsightRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _insights = null;
      _study = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final sample = AppDependenciesScope.of(context).sampleContent;
    final today = _today;
    final insights = _insights;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // The last item can scroll clear of the floating Ask OmniAI button.
        padding: EdgeInsets.fromLTRB(18, 18, 18, askOmniaClearance(context)),
        children: [
          Semantics(
            header: true,
            child: const Text(
              'Insights',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            sample
                ? 'Patterns from what you log  ·  SAMPLE DATA'
                : 'Patterns from what you log',
            style: TextStyle(color: context.mutedForeground),
          ),
          const SizedBox(height: 18),
          ChoiceSegments<InsightRange>(
            label: 'Range',
            showLabel: false,
            options: const [
              SelectOption(InsightRange.week, 'Week'),
              SelectOption(InsightRange.month, 'Month'),
            ],
            selected: _range,
            onChanged: _select,
          ),
          const SizedBox(height: 12),
          if (today != null)
            Text(
              _spanLabel(_range, today),
              style: OmniaText.meta.copyWith(color: context.mutedForeground),
            ),
          const SizedBox(height: 14),
          if (today == null || (_loading && insights == null))
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading insights',
                ),
              ),
            )
          else if (_error != null && insights == null)
            ErrorView(
              title: "Couldn't load insights",
              error: _error!,
              onRetry: _load,
            )
          else if (insights != null) ...[
            if (!insights.hasData)
              EmptyCard(
                title: _range == InsightRange.week
                    ? 'Nothing logged this week yet.'
                    : 'Nothing logged this month yet.',
                detail:
                    'Log steps and workouts from Today or Areas. Insights '
                    'only use days you log.',
              )
            else ...[
              _WorkoutCard(insights: insights),
              const SizedBox(height: 16),
              _StepsCard(insights: insights),
              const SizedBox(height: 12),
              Text(
                insights.notLoggedDays == 0
                    ? 'Every day so far is logged.'
                    : '${_days(insights.notLoggedDays)} not logged. They '
                          'are left out of every figure, not counted as zero.',
                style: TextStyle(color: context.mutedForeground),
              ),
            ],
            const SizedBox(height: 16),
            if (_study case final study? when study.hasData)
              _StudyCard(insights: study)
            else if (_studyFailed)
              Text(
                "Couldn't load study time. Pull down to try again.",
                style: TextStyle(color: context.mutedForeground),
              )
            else
              Text(
                'No study recorded ${_range == InsightRange.week ? 'this week' : 'this month'} yet. '
                'Focus sessions and study blocks you check off show up here.',
                style: TextStyle(color: context.mutedForeground),
              ),
          ],
        ],
      ),
    );
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({required this.insights});
  final StudyInsights insights;

  @override
  Widget build(BuildContext context) => _InsightCard(
    title: 'Study',
    headline: '${formatMinutes(insights.totalMinutes)} studied',
    detail: [
      'On ${insights.studiedDays} of ${_days(insights.elapsedDays)} so far',
      if (insights.planMinutes > 0)
        '${formatMinutes(insights.planMinutes)} from plan check-offs',
      if (insights.focusMinutes > 0)
        '${formatMinutes(insights.focusMinutes)} from Focus',
    ].join(' · '),
    grid: HabitGrid(
      days: insights.days,
      stateOf: insights.state,
      accent: blue,
      describe: (day, state) => switch (state) {
        DayState.hit => '${formatMinutes(insights.minutesOn(day.day))} studied',
        DayState.upcoming => 'upcoming',
        _ => 'no study recorded',
      },
    ),
    legend: const [
      (DayState.hit, 'Studied'),
      (DayState.logged, 'No study recorded'),
    ],
    accent: blue,
  );
}

String _days(int n) => n == 1 ? '1 day' : '$n days';

const _monthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _spanLabel(InsightRange range, DateTime today) {
  final span = insightSpan(range, today);
  String short(DateTime day) => '${_monthsShort[day.month - 1]} ${day.day}';
  return switch (range) {
    InsightRange.week =>
      'THIS WEEK  ·  ${short(span.from)} – ${short(span.to)}',
    InsightRange.month =>
      'THIS MONTH  ·  ${_monthsShort[span.from.month - 1].toUpperCase()} ${span.from.year}',
  };
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.insights});
  final ActivityInsights insights;

  @override
  Widget build(BuildContext context) {
    final rate = insights.workoutRate;
    return _InsightCard(
      title: 'Workouts',
      headline:
          '${insights.workoutDays} '
          '${insights.workoutDays == 1 ? 'workout' : 'workouts'} in '
          '${_days(insights.loggedDays)} logged',
      detail: [
        if (insights.workoutMinutes > 0)
          '${formatMinutes(insights.workoutMinutes)} in total',
        rate == null
            ? 'Log at least $minDaysForRates days for a consistency rate.'
            : '${(rate * 100).round()}% of logged days had a workout.',
      ].join(' · '),
      grid: HabitGrid(
        days: insights.days,
        stateOf: insights.workoutState,
        accent: mint,
        describe: (day, state) => switch (state) {
          DayState.hit =>
            'workout'
                '${day.activity!.workoutMinutes > 0 ? ', ${day.activity!.workoutMinutes} minutes' : ''}',
          DayState.logged => 'no workout',
          DayState.notLogged => 'not logged',
          DayState.upcoming => 'upcoming',
        },
      ),
      legend: const [
        (DayState.hit, 'Workout'),
        (DayState.logged, 'No workout'),
        (DayState.notLogged, 'Not logged'),
      ],
      accent: mint,
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.insights});
  final ActivityInsights insights;

  @override
  Widget build(BuildContext context) {
    final average = insights.averageSteps;
    final goal = insights.stepGoal;
    return _InsightCard(
      title: 'Steps',
      headline: average == null
          ? 'No steps logged'
          : '${formatCount(average)} a day on average',
      detail: goal <= 0
          ? 'No daily step goal is set.'
          : '${insights.daysAtStepGoal} of ${_days(insights.loggedDays)} '
                'logged reached ${formatCount(goal)}.',
      grid: HabitGrid(
        days: insights.days,
        stateOf: insights.stepState,
        accent: blue,
        describe: (day, state) => switch (state) {
          DayState.hit || DayState.logged =>
            '${formatCount(day.activity!.steps)} steps'
                '${state == DayState.hit ? ', goal reached' : ''}',
          DayState.notLogged => 'not logged',
          DayState.upcoming => 'upcoming',
        },
      ),
      legend: [
        (DayState.hit, goal > 0 ? 'At goal' : 'Logged'),
        if (goal > 0) (DayState.logged, 'Below goal'),
        (DayState.notLogged, 'Not logged'),
      ],
      accent: blue,
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.headline,
    required this.detail,
    required this.grid,
    required this.legend,
    required this.accent,
  });
  final String title, headline, detail;
  final Widget grid;
  final List<(DayState, String)> legend;
  final Color accent;

  @override
  Widget build(BuildContext context) => HardCard(
    color: paper,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title.toUpperCase(),
            style: OmniaText.label.copyWith(color: context.mutedForeground),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          headline,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(detail),
        const SizedBox(height: 14),
        grid,
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final (state, label) in legend)
              ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HabitCell(state: state, accent: accent, size: 14),
                    const SizedBox(width: 6),
                    Flexible(child: Text(label, style: OmniaText.meta)),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
