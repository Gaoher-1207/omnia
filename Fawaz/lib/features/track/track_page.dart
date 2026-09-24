import 'package:flutter/material.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/format.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/domain/dashboard.dart';
import 'package:omnia_ui/features/study/domain/study_plan.dart';
import 'package:omnia_ui/features/study/study_page.dart';
import 'package:omnia_ui/features/tasks/tasks_page.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';
import 'package:omnia_ui/features/track/log_pages.dart';
import 'package:omnia_ui/features/track/meals_page.dart';
import 'package:omnia_ui/features/track/widgets/activity_line.dart';
import 'package:omnia_ui/features/track/widgets/bar_chart.dart';
import 'package:omnia_ui/features/track/widgets/track_tile.dart';

/// What happened today and the last two weeks of steps.
class _TrackData {
  const _TrackData({required this.sessions, required this.meals, required this.days});
  final List<StudyLog> sessions;
  final DayMeals meals;
  final List<ActivityDay> days;
}

class TrackPage extends StatefulWidget {
  const TrackPage({super.key});
  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage> {
  late final deps = AppDependenciesScope.of(context);
  late final feed = Loadable<_TrackData>(_loadFeed);
  TabState? _tab;

  Future<_TrackData> _loadFeed() async {
    final today = ControllerScope.read<DashboardState>(context).data?.date ?? DateUtils.dateOnly(DateTime.now());
    final results = await Future.wait<Object>([
      deps.study.getSessions(from: today, to: today),
      deps.track.meals(today),
      deps.track.activityRange(today.subtract(const Duration(days: 13)), today),
    ]);
    return _TrackData(
      sessions: results[0] as List<StudyLog>,
      meals: results[1] as DayMeals,
      days: results[2] as List<ActivityDay>,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tab = ControllerScope.of<TabState>(context);
    if (!identical(tab, _tab)) {
      _tab?.removeListener(_onTab);
      _tab = tab..addListener(_onTab);
    }
  }

  void _onTab() {
    if (_tab?.value == 2) _refresh();
  }

  Future<void> _refresh() async {
    await Future.wait([feed.load(), SessionScope.refreshDashboard(context)]);
  }

  Future<void> _open(Widget page) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await _refresh();
  }

  @override
  void dispose() {
    _tab?.removeListener(_onTab);
    feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ControllerScope.of<DashboardState>(context);
    final data = dashboard.data;
    if (data == null) {
      return dashboard.error == null
          ? const LoadingView()
          : ErrorView(error: dashboard.error!, onRetry: dashboard.load);
    }
    if (!feed.hasData && !feed.loading && feed.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) feed.load();
      });
    }
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(18),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const Text('Track', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Your day at a glance  ·  ${longDate(data.date)}'),
            const SizedBox(height: 20),
            ..._tiles(data.today),
            const SizedBox(height: 15),
            const Text('Today’s activity', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            _todayCard(data),
            const SizedBox(height: 20),
            const Text('Steps, last 14 days', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            _chart(data.today.stepGoal),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  List<Widget> _tiles(TodaySummary t) => [
    TrackTile(
      icon: Icons.menu_book_outlined,
      name: 'Study',
      amount: hoursLabel(t.studyMinutes),
      goal: '${hoursLabel(t.studyGoalMinutes)} goal',
      progress: ratio(t.studyMinutes, t.studyGoalMinutes),
      color: blue,
      onTap: () => _open(const StudyPage()),
    ),
    TrackTile(
      icon: Icons.task_alt,
      name: 'Tasks',
      amount: '${t.tasksCompleted} of ${t.taskGoal}',
      goal: 'tasks done',
      progress: ratio(t.tasksCompleted, t.taskGoal),
      color: yellow,
      onTap: () => _open(const TasksPage()),
    ),
    TrackTile(
      icon: Icons.directions_walk,
      name: 'Activity',
      amount: thousands(t.steps),
      goal: '${thousands(t.stepGoal)} steps${t.workoutDone ? ' · workout ✓' : ''}',
      progress: ratio(t.steps, t.stepGoal),
      color: mint,
      onTap: () => _open(const ActivityLogPage()),
    ),
    TrackTile(
      icon: Icons.dark_mode_outlined,
      name: 'Sleep',
      amount: t.sleepMinutes == null ? 'Not logged' : hoursLabel(t.sleepMinutes!),
      goal: '${hoursLabel(t.sleepGoalMinutes)} goal',
      progress: ratio(t.sleepMinutes ?? 0, t.sleepGoalMinutes),
      color: lilac,
      onTap: () => _open(const SleepLogPage()),
    ),
    TrackTile(
      icon: Icons.restaurant_outlined,
      name: 'Food',
      amount: '${thousands(t.calories)} kcal',
      goal: '${thousands(t.calorieGoal)} kcal goal',
      progress: ratio(t.calories, t.calorieGoal),
      color: paper,
      onTap: () => _open(const MealsPage()),
    ),
  ];

  Widget _todayCard(Dashboard data) {
    final value = feed.data;
    if (value == null) {
      return HardCard(
        color: paper,
        child: feed.error == null
            ? const LoadingView()
            : ErrorView(error: feed.error!, onRetry: feed.load),
      );
    }
    final lines = <Widget>[
      for (final s in value.sessions)
        ActivityLine(
          icon: Icons.menu_book_outlined,
          title: '${s.subjectName ?? 'Study'} study',
          time: hoursLabel(s.minutes),
        ),
      if (data.today.workoutDone)
        ActivityLine(
          icon: Icons.fitness_center,
          title: value.days.isEmpty || value.days.last.workoutType == null
              ? 'Workout'
              : value.days.last.workoutType!,
          time: data.today.workoutMinutes > 0 ? '${data.today.workoutMinutes}m' : 'done',
        ),
      if (data.today.sleepMinutes != null)
        ActivityLine(icon: Icons.dark_mode_outlined, title: 'Slept', time: hoursLabel(data.today.sleepMinutes!)),
      for (final meal in value.meals.meals)
        ActivityLine(
          icon: Icons.restaurant_outlined,
          title: '${meal.type.name[0].toUpperCase()}${meal.type.name.substring(1)}: ${meal.description}',
          time: '${meal.calories} kcal',
        ),
      if (data.today.tasksCompleted > 0)
        ActivityLine(
          icon: Icons.check,
          title: '${data.today.tasksCompleted} ${data.today.tasksCompleted == 1 ? 'task' : 'tasks'} completed',
          time: 'today',
        ),
    ];
    return HardCard(
      color: paper,
      child: lines.isEmpty
          ? Text(
              'Nothing logged yet today. Tap a tile above to add study, activity, sleep or food.',
              style: TextStyle(color: context.mutedForeground),
            )
          : Column(
              children: [
                for (var i = 0; i < lines.length; i++) ...[if (i > 0) const Divider(), lines[i]],
              ],
            ),
    );
  }

  Widget _chart(int goal) {
    final days = feed.data?.days;
    if (days == null) return const SizedBox(height: 120, child: LoadingView());
    return HardCard(
      color: mint,
      child: BarChart(
        values: [for (final d in days) d.steps.toDouble()],
        labels: [for (final d in days) 'MTWTFSS'[d.day.weekday - 1]],
        color: context.cardForeground(mint),
        goal: goal.toDouble(),
        highlights: [for (final d in days) d.workoutDone],
        caption: '${days.where((d) => goal > 0 && d.steps >= goal).length} of ${days.length} days at goal · '
            '${days.where((d) => d.workoutDone).length} workouts (dots)',
      ),
    );
  }
}
