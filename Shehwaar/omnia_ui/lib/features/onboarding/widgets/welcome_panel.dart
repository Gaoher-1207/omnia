import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/surface_shadow.dart';

class WelcomePanel extends StatelessWidget {
  const WelcomePanel({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // Read viewport width without introducing LayoutBuilder into an intrinsic
    // height layout. The same maximum width is used by the onboarding shell.
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 560.0) - 48;
    final wordmarkSize = (width * .13).clamp(40.0, 60.0);
    final headlineSize = (width * .108).clamp(30.0, 48.0);
    final markSize = (width * .34).clamp(96.0, 150.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.center,
          child: Semantics(
            label: 'Omnia logo',
            image: true,
            child: SizedBox.square(
              dimension: markSize,
              child: const FittedBox(child: OmniaMark(lifted: false)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'omnia',
          style: TextStyle(
            color: context.foreground,
            fontSize: wordmarkSize,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Everything. One plan.',
          style: TextStyle(
            color: context.mutedForeground,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Flexible gaps spread the groups on tall screens, collapse on short.
        const Spacer(),
        const SizedBox(height: 24),
        Text(
          'A MORE\nBALANCED\nYOU IS CLOSER\nTHAN YOU THINK.',
          style: TextStyle(
            color: context.foreground,
            fontSize: headlineSize,
            fontWeight: FontWeight.w900,
            height: 1.02,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Bring your study, tasks, fitness, nutrition, sleep and habits '
          'together — and let Omnia create a plan that adapts to you.',
          style: TextStyle(
            color: context.mutedForeground,
            fontSize: 17,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        const Spacer(flex: 2),
        SizedBox(
          width: double.infinity,
          child: SurfaceShadow(
            radius: 9,
            offset: const Offset(2, 2),
            child: FilledButton(
              onPressed: onNext,
              style: FilledButton.styleFrom(
                backgroundColor: context.actionBackground,
                foregroundColor: context.actionForeground,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'GET STARTED',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Icon(Icons.arrow_forward),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
