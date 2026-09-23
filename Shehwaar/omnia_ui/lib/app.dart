import 'package:flutter/material.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/features/onboarding/onboarding_page.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/theme/theme_controller.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';
import 'package:omnia_ui/features/tasks/task_controller.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/insights/insights_page.dart';
import 'package:omnia_ui/features/plan/plan_page.dart';
import 'package:omnia_ui/features/track/track_page.dart';

class OmniaApp extends StatefulWidget {
  const OmniaApp({super.key, this.dependencies});

  /// Defaults to in-memory mocks; inject API-backed repositories here later.
  final AppDependencies? dependencies;
  @override
  State<OmniaApp> createState() => _OmniaAppState();
}

class _OmniaAppState extends State<OmniaApp> {
  // In-memory first-run gate. Load/save a local preference here when persistent
  // onboarding completion is introduced; no feature page needs to know about it.
  bool _onboardingComplete = false;
  final theme = ThemeController();
  late final dependencies = widget.dependencies ?? AppDependencies.mock();
  late final revision = RevisionController(
    session: dependencies.initialRevisionSession,
    repository: dependencies.study,
  );
  late final tasks = TaskController(dependencies.tasks)..load();
  final focusTimer = FocusTimerController();

  @override
  void dispose() {
    theme.dispose();
    revision.dispose();
    tasks.dispose();
    focusTimer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDependenciesScope(
    dependencies: dependencies,
    child: ThemeScope(
      controller: theme,
      child: RevisionScope(
        controller: revision,
        child: TaskScope(
          controller: tasks,
          child: FocusTimerScope(
            controller: focusTimer,
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: theme,
              builder: (context, mode, _) => MaterialApp(
                title: 'Omnia',
                debugShowCheckedModeBanner: false,
                theme: buildAppTheme(),
                darkTheme: buildAppTheme(brightness: Brightness.dark),
                themeMode: mode,
                home: _onboardingComplete
                    ? const OmniaHome()
                    : OnboardingPage(
                        onSkip: () =>
                            setState(() => _onboardingComplete = true),
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class OmniaHome extends StatefulWidget {
  const OmniaHome({super.key});
  @override
  State<OmniaHome> createState() => _OmniaHomeState();
}

class _OmniaHomeState extends State<OmniaHome> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        openPlan: () => setState(() => tab = 1),
        openTrack: () => setState(() => tab = 2),
      ),
      const PlanPage(),
      const TrackPage(),
      const InsightsPage(),
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: IndexedStack(index: tab, children: pages),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.navigationSurface,
          border: Border(top: BorderSide(color: context.outline, width: 1.5)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _nav(0, Icons.home_rounded, 'Home', dark),
              _nav(1, Icons.calendar_month_outlined, 'Plan', dark),
              _nav(2, Icons.bar_chart_rounded, 'Track', dark),
              _nav(3, Icons.pie_chart_outline, 'Insights', dark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nav(int index, IconData icon, String title, bool dark) {
    final active = tab == index;
    final color = context.foreground;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => tab = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: active
                      ? Border.all(
                          color: context.outlineOn(
                            dark ? darkNavigationAccent : blue,
                          ),
                          width: 1.5,
                        )
                      : null,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? (dark ? darkNavigationAccent : blue)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    size: 23,
                    color: active ? ink : color.withValues(alpha: .65),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
