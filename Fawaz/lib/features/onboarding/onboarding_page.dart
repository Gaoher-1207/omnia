import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/onboarding/widgets/onboarding_footer.dart';
import 'package:omnia_ui/features/onboarding/widgets/welcome_panel.dart';

/// Presentation only: the caller decides how completion is stored and routed.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onSkip});
  final VoidCallback onSkip;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(
    page,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeInOut,
  );

  @override
  Widget build(BuildContext context) {
    // Add future page widgets here; indicator count follows this list.
    final pages = <Widget>[
      WelcomePanel(onNext: () => _goTo(1)),
      _ReadyPanel(onBack: () => _goTo(0), onContinue: widget.onSkip),
    ];
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextButton(
                      onPressed: widget.onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: context.foreground,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      child: const Text('SKIP →'),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    children: [
                      for (var index = 0; index < pages.length; index++)
                        _OnboardingLayout(
                          pageIndex: index,
                          pageCount: pages.length,
                          child: pages[index],
                        ),
                    ],
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

/// Fills tall viewports, but grows vertically and scrolls when content needs it.
class _OnboardingLayout extends StatelessWidget {
  const _OnboardingLayout({
    required this.child,
    required this.pageIndex,
    required this.pageCount,
  });
  final Widget child;
  final int pageIndex, pageCount;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: PageStorageKey('onboarding-$pageIndex'),
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        sliver: SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              const SizedBox(height: 24),
              OnboardingFooter(pageIndex: pageIndex, pageCount: pageCount),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Last step: explain what happens next and continue to sign-in.
class _ReadyPanel extends StatelessWidget {
  const _ReadyPanel({required this.onBack, required this.onContinue});
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        'One plan that adapts',
        style: TextStyle(
          color: context.foreground,
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Add your exams, backlog and tasks, log activity, sleep and meals, '
        'and Omnia builds a realistic plan for your day. It adjusts when '
        'something is missed or you slept badly.',
        style: TextStyle(color: context.mutedForeground, height: 1.5),
      ),
      const SizedBox(height: 24),
      SolidAction(label: 'CONTINUE', onTap: onContinue),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back'),
      ),
    ],
  );
}
