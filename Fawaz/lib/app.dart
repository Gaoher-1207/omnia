import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_config.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/auth/auth_page.dart';
import 'package:omnia_ui/features/onboarding/onboarding_page.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/theme/theme_controller.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/insights/insights_page.dart';
import 'package:omnia_ui/features/plan/plan_page.dart';
import 'package:omnia_ui/features/track/track_page.dart';

class OmniaApp extends StatefulWidget {
  const OmniaApp({super.key, this.dependencies});

  /// Defaults to the real backend at [ApiConfig.resolveBaseUrl]; tests inject
  /// dependencies backed by a fake HTTP client.
  final AppDependencies? dependencies;
  @override
  State<OmniaApp> createState() => _OmniaAppState();
}

class _OmniaAppState extends State<OmniaApp> {
  // In-memory first-run gate for signed-out visitors. Signed-in users skip it.
  bool _onboardingComplete = false;
  final theme = ThemeController();
  late final AppDependencies? dependencies = widget.dependencies ?? _production();
  late final AuthController? auth = dependencies == null
      ? null
      : (AuthController(dependencies!.api)..restore());

  static AppDependencies? _production() {
    final baseUrl = ApiConfig.resolveBaseUrl();
    return baseUrl == null ? null : AppDependencies.production(baseUrl);
  }

  @override
  void dispose() {
    theme.dispose();
    auth?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = dependencies;
    final controller = auth;
    Widget app(Widget home) => ValueListenableBuilder<ThemeMode>(
      valueListenable: theme,
      builder: (context, mode, _) => MaterialApp(
        title: 'Omnia',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(brightness: Brightness.dark),
        themeMode: mode,
        home: home,
      ),
    );
    if (deps == null || controller == null) {
      return ThemeScope(controller: theme, child: app(const _MissingConfiguration()));
    }
    return AppDependenciesScope(
      dependencies: deps,
      child: ThemeScope(
        controller: theme,
        child: AuthScope(
          controller: controller,
          // Session state sits above MaterialApp so pushed screens can reach it.
          // Signing in or out swaps the whole tree, which also clears any
          // screens that were open.
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final user = controller.user;
              if (controller.status == AuthStatus.signedIn && user != null) {
                // Past the intro: signing out or an expired session goes
                // straight back to sign-in, not onboarding.
                _onboardingComplete = true;
                return SessionScope(key: ValueKey(user.id), child: app(const OmniaHome()));
              }
              return app(
                _SignedOut(
                  onboardingComplete: _onboardingComplete,
                  onOnboardingDone: () => setState(() => _onboardingComplete = true),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Start-up, onboarding and sign-in.
class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.onboardingComplete, required this.onOnboardingDone});
  final bool onboardingComplete;
  final VoidCallback onOnboardingDone;

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    if (auth.status == AuthStatus.unknown) {
      final error = auth.restoreError;
      return error == null
          ? const _Splash()
          : Scaffold(
              body: SafeArea(
                child: ErrorView(
                  title: "Couldn't reach OMNIA",
                  error: error,
                  onRetry: auth.restore,
                ),
              ),
            );
    }
    return onboardingComplete ? const AuthPage() : OnboardingPage(onSkip: onOnboardingDone);
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    body: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OmniaMark(),
          SizedBox(height: 18),
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        ],
      ),
    ),
  );
}

/// Release builds must be told where the backend is.
class _MissingConfiguration extends StatelessWidget {
  const _MissingConfiguration();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: MessageView(
        title: 'Server not configured',
        detail:
            'This build has no API_BASE_URL. Rebuild with '
            '--dart-define=API_BASE_URL=https://your-server/api',
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

  void _select(int index) {
    setState(() => tab = index);
    ControllerScope.read<TabState>(context).value = index;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(openPlan: () => _select(1), openTrack: () => _select(2)),
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
        onTap: () => _select(index),
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
                      ? Border.all(color: context.outline, width: 1.5)
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
