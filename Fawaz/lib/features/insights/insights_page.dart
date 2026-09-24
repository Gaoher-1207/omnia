import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/format.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/insights/domain/progress.dart';
import 'package:omnia_ui/features/track/widgets/bar_chart.dart';

class _InsightsData {
  const _InsightsData(this.progress, this.achievements);
  final Progress progress;
  final List<Achievement> achievements;
}

/// Streaks, the last two weeks, and achievements. Streak rules live on the
/// backend; this screen only presents them.
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});
  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  late final deps = AppDependenciesScope.of(context);
  late final data = Loadable<_InsightsData>(() async {
    final results = await Future.wait<Object>([deps.progress.progress(days: 14), deps.progress.achievements()]);
    return _InsightsData(results[0] as Progress, results[1] as List<Achievement>);
  });
  TabState? _tab;

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
    if (_tab?.value == 3) data.load();
  }

  @override
  void dispose() {
    _tab?.removeListener(_onTab);
    data.dispose();
    super.dispose();
  }

  Future<void> _share(Achievement achievement) async {
    try {
      await deps.social.shareAchievement(achievement.code);
      if (mounted) showDone(context, 'Shared “${achievement.title}” with your friends.');
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!data.hasData && !data.loading && data.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) data.load();
      });
    }
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final value = data.data;
        return RefreshIndicator(
          onRefresh: data.load,
          child: ListView(
            padding: const EdgeInsets.all(18),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const Text('Insights', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              const Text('Patterns across your last two weeks'),
              const SizedBox(height: 24),
              if (value == null)
                data.error == null ? const LoadingView() : ErrorView(error: data.error!, onRetry: data.load)
              else
                ..._content(value),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _content(_InsightsData value) {
    final history = value.progress.history;
    final week = history.length > 7 ? history.sublist(history.length - 7) : history;
    final studyWeek = week.fold<int>(0, (sum, d) => sum + d.studyMinutes);
    final tasksWeek = week.fold<int>(0, (sum, d) => sum + d.tasksCompleted);
    final balanced = week.where((d) => d.balanced).length;
    final avgSteps = week.isEmpty ? 0 : week.fold<int>(0, (sum, d) => sum + d.steps) ~/ week.length;
    final sleeps = [for (final d in week) if (d.sleepMinutes != null) d.sleepMinutes!];
    final streaks = value.progress.streaks;
    return [
      HardCard(
        color: lilac,
        prominent: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OmniaMark(),
            const SizedBox(height: 12),
            const Text('Your week in perspective', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              'In the last 7 days you studied ${hoursLabel(studyWeek)}, finished $tasksWeek '
              '${tasksWeek == 1 ? 'task' : 'tasks'} and averaged ${thousands(avgSteps)} steps. '
              '$balanced of 7 days were balanced'
              '${sleeps.isEmpty ? '.' : ', and you slept ${hoursLabel(sleeps.reduce((a, b) => a + b) ~/ sleeps.length)} a night on average.'}',
              style: const TextStyle(height: 1.35),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text('Streaks', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 9),
      Row(
        children: [
          Expanded(child: _StreakCard('Study', streaks.study, blue)),
          const SizedBox(width: 10),
          Expanded(child: _StreakCard('Tasks', streaks.tasks, yellow)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _StreakCard('Fitness', streaks.fitness, mint)),
          const SizedBox(width: 10),
          Expanded(child: _StreakCard('Balance', streaks.balance, lilac)),
        ],
      ),
      const SizedBox(height: 18),
      const Text('Study, last 14 days', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 9),
      HardCard(
        color: blue,
        child: BarChart(
          values: [for (final d in history) d.studyMinutes.toDouble()],
          labels: [for (final d in history) 'MTWTFSS'[d.date.weekday - 1]],
          color: context.cardForeground(blue),
          highlights: [for (final d in history) d.balanced],
          caption: '${hoursLabel(history.fold<int>(0, (s, d) => s + d.studyMinutes))} in total · dots mark balanced days',
        ),
      ),
      if (history.any((d) => d.sleepMinutes != null)) ...[
        const SizedBox(height: 18),
        const Text('Sleep, last 14 days', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 9),
        HardCard(
          color: lilac,
          child: BarChart(
            values: [for (final d in history) (d.sleepMinutes ?? 0) / 60],
            labels: [for (final d in history) 'MTWTFSS'[d.date.weekday - 1]],
            color: context.cardForeground(lilac),
            caption: 'Hours per night',
          ),
        ),
      ],
      const SizedBox(height: 18),
      const Text('Achievements', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 9),
      for (final a in value.achievements)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HardCard(
            shadowOffset: const Offset(2, 3),
            color: a.earned ? yellow : paper,
            child: Row(
              children: [
                Icon(a.earned ? Icons.emoji_events : Icons.emoji_events_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(a.description, style: const TextStyle(fontSize: 12)),
                      if (!a.earned) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: ratio(a.progress, a.target),
                            minHeight: 6,
                            backgroundColor: context.progressTrack(paper),
                            color: context.foreground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (a.earned)
                  TextButton(onPressed: () => _share(a), child: const Text('Share')),
              ],
            ),
          ),
        ),
    ];
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard(this.name, this.streak, this.color);
  final String name;
  final Streak streak;
  final Color color;

  @override
  Widget build(BuildContext context) => HardCard(
    shadowOffset: const Offset(2, 3),
    color: color,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('${streak.current}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        Text(
          '${streak.current == 1 ? 'day' : 'days'} · best ${streak.longest}${streak.activeToday ? ' · ✓ today' : ''}',
          style: const TextStyle(fontSize: 11),
        ),
      ],
    ),
  );
}
