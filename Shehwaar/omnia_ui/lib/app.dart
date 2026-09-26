import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_config.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/auth/token_store.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/auth/auth_page.dart';
import 'package:omnia_ui/features/focus/focus_timer_controller.dart';
import 'package:omnia_ui/features/focus/widgets/focus_phase_feedback.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/features/onboarding/onboarding_page.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/theme/theme_controller.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/insights/insights_page.dart';
import 'package:omnia_ui/features/plan/plan_page.dart';
import 'package:omnia_ui/features/areas/areas_page.dart';

class OmniaApp extends StatefulWidget {
  const OmniaApp({super.key, this.dependencies, this.api});

  /// Feature repositories for every session; null gives each session fresh
  /// in-memory mocks. API-backed repositories arrive feature by feature.
  final AppDependencies? dependencies;

  /// The backend. When set, or when built with `--dart-define=OMNIA_DATA=api`,
  /// the app signs in first; otherwise it runs on mock data with no sign-in.
  final ApiClient? api;
  @override
  State<OmniaApp> createState() => _OmniaAppState();
}

class _OmniaAppState extends State<OmniaApp> {
  // In-memory first-run gate. Load/save a local preference here when persistent
  // onboarding completion is introduced; no feature page needs to know about it.
  bool _onboardingComplete = false;
  // App-lifetime state; per-user state lives in [UserSession].
  final theme = ThemeController();
  final focusTimer = FocusTimerController();
  late final ApiClient? api = widget.api ?? _environmentApi();
  late final AuthController? auth = api == null
      ? null
      : (AuthController(api!)..restore());

  /// Null when not in API mode, or a release build has no OMNIA_API_BASE_URL.
  static ApiClient? _environmentApi() {
    final url = ApiConfig.apiMode ? ApiConfig.resolveBaseUrl() : null;
    return url == null
        ? null
        : ApiClient(baseUrl: url, tokens: SecureTokenStore());
  }

  @override
  void dispose() {
    theme.dispose();
    focusTimer.dispose();
    auth?.dispose();
    if (widget.api == null) api?.close();
    super.dispose();
  }

  void _finishOnboarding() => setState(() => _onboardingComplete = true);

  Widget _app(Widget home) => ValueListenableBuilder<ThemeMode>(
    valueListenable: theme,
    builder: (context, mode, _) => MaterialApp(
      title: 'Omnia',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: mode,
      builder: (context, child) =>
          FocusPhaseFeedback(controller: focusTimer, child: child!),
      home: home,
    ),
  );

  /// A new session's repositories: server-backed Tasks once signed in (API
  /// mode), in-memory mocks otherwise, or whatever a test injected.
  AppDependencies _newDependencies() =>
      widget.dependencies ??
      (auth == null ? AppDependencies.mock() : AppDependencies.api(api!));

  // Session state sits above MaterialApp so pushed screens can reach it.
  Widget _session(Widget home, {Key? key}) => UserSession(
    key: key,
    dependencies: _newDependencies,
    child: _app(home),
  );

  Widget _body() {
    final auth = this.auth;
    if (auth == null) {
      if (ApiConfig.apiMode) return _app(const _MissingConfiguration());
      return _session(
        _onboardingComplete
            ? const OmniaHome()
            : OnboardingPage(onSkip: _finishOnboarding),
      );
    }
    return AuthScope(
      controller: auth,
      // Signing in or out swaps the whole tree, which also closes any
      // screens that were open and disposes the previous user's session.
      child: ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          final user = auth.user;
          if (auth.status == AuthStatus.signedIn && user != null) {
            // Past the intro: signing out or an expired session goes
            // straight back to sign-in, not onboarding.
            _onboardingComplete = true;
            return _session(const OmniaHome(), key: ValueKey(user.id));
          }
          return _app(
            _SignedOut(
              onboardingComplete: _onboardingComplete,
              onOnboardingDone: _finishOnboarding,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ThemeScope(
    controller: theme,
    child: FocusTimerScope(controller: focusTimer, child: _body()),
  );
}

/// Start-up, onboarding and sign-in, in API mode.
class _SignedOut extends StatelessWidget {
  const _SignedOut({
    required this.onboardingComplete,
    required this.onOnboardingDone,
  });
  final bool onboardingComplete;
  final VoidCallback onOnboardingDone;

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    if (auth.status == AuthStatus.unknown) {
      final error = auth.restoreError;
      return Scaffold(
        backgroundColor: context.colors.surface,
        body: SafeArea(
          child: error == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OmniaMark(),
                      SizedBox(height: 18),
                      CircularProgressIndicator(
                        semanticsLabel: 'Starting OMNIA',
                      ),
                    ],
                  ),
                )
              : ErrorView(
                  title: "Couldn't reach OMNIA",
                  error: error,
                  onRetry: auth.restore,
                ),
        ),
      );
    }
    return onboardingComplete
        ? const AuthPage()
        : OnboardingPage(onSkip: onOnboardingDone);
  }
}

/// API mode in a release build that wasn't told where the backend is.
class _MissingConfiguration extends StatelessWidget {
  const _MissingConfiguration();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: MessageView(
        title: 'Server not configured',
        detail:
            'This build has no OMNIA_API_BASE_URL. Rebuild with '
            '--dart-define=OMNIA_API_BASE_URL=https://your-server/api',
      ),
    ),
  );
}

/// The root tabs, in order. Their labels live only here, so renaming one
/// ("Areas" is a working name) is a one-line change.
enum RootTab {
  today('Today', Icons.home_rounded),
  plan('Plan', Icons.calendar_month_outlined),
  areas('Areas', Icons.grid_view_rounded),
  insights('Insights', Icons.pie_chart_outline);

  const RootTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The signed-in shell. Each tab keeps its own navigation stack, so an
/// area's screens (Tasks, Goals, Study…) open under the bottom bar and each
/// tab is where it was left. Forms and editors are pushed on the app's root
/// navigator instead and take the full screen.
class OmniaHome extends StatefulWidget {
  const OmniaHome({super.key});
  @override
  State<OmniaHome> createState() => _OmniaHomeState();
}

class _OmniaHomeState extends State<OmniaHome> {
  var tab = RootTab.today;
  final _stacks = {
    for (final tab in RootTab.values) tab: GlobalKey<NavigatorState>(),
  };

  /// Choosing the open tab again returns it to its first screen.
  void _select(RootTab next) {
    if (next == tab) {
      _stacks[next]!.currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => tab = next);
    }
  }

  Widget _root(RootTab tab) => switch (tab) {
    RootTab.today => HomePage(openPlan: () => _select(RootTab.plan)),
    RootTab.plan => const PlanPage(),
    RootTab.areas => const AreasPage(),
    RootTab.insights => const InsightsPage(),
  };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: IndexedStack(
          index: tab.index,
          children: [
            for (final option in RootTab.values)
              // System back pops the visible tab's own stack first.
              NavigatorPopHandler<Object?>(
                enabled: option == tab,
                onPopWithResult: (_) => _stacks[option]!.currentState?.maybePop(),
                child: Navigator(
                  key: _stacks[option],
                  onGenerateRoute: (_) =>
                      MaterialPageRoute(builder: (_) => _root(option)),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.navigationSurface,
          border: Border(top: BorderSide(color: context.outline, width: 1.5)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [for (final option in RootTab.values) _nav(option, dark)],
          ),
        ),
      ),
    );
  }

  Widget _nav(RootTab option, bool dark) {
    final active = tab == option;
    final color = context.foreground;
    return Expanded(
      // One merged node per tab: "Plan, selected, button".
      child: Semantics(
        container: true,
        button: true,
        selected: active,
        child: InkWell(
          onTap: () => _select(option),
          focusColor: color.withValues(alpha: .16),
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
                      option.icon,
                      size: 23,
                      color: active ? ink : color.withValues(alpha: .65),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
