import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/features/onboarding/widgets/onboarding_action.dart';

/// The second intro step: what Omnia actually does, in three steps that match
/// the app as it exists (no promises of features that aren't built).
class HowItWorksPanel extends StatelessWidget {
  const HowItWorksPanel({
    super.key,
    required this.onBack,
    required this.onFinish,
  });
  final VoidCallback onBack, onFinish;

  static const steps = [
    (
      color: blue,
      title: 'Bring it together',
      body: 'Tasks, study, activity and sleep live in one place.',
    ),
    (
      color: yellow,
      title: 'Get a plan for today',
      body:
          'Omnia suggests a plan that fits your free time and fixed '
          'commitments.',
    ),
    (
      color: mint,
      title: 'Stay in control',
      body:
          'Ask for a change and preview it first. Nothing changes until '
          'you approve it.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 560.0) - 48;
    final headlineSize = (width * .095).clamp(28.0, 42.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text(
            'ONE PLAN.\nBUILT AROUND\nYOUR DAY.',
            style: TextStyle(
              color: context.foreground,
              fontSize: headlineSize,
              fontWeight: FontWeight.w900,
              height: 1.02,
              letterSpacing: -.8,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'How Omnia works',
          style: TextStyle(
            color: context.mutedForeground,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        const SizedBox(height: 20),
        for (final (index, step) in steps.indexed) ...[
          if (index > 0) const SizedBox(height: 12),
          _Step(
            number: index + 1,
            color: step.color,
            title: step.title,
            body: step.body,
          ),
        ],
        const SizedBox(height: 28),
        const Spacer(flex: 2),
        OnboardingAction(label: 'ENTER OMNIA', onPressed: onFinish),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onBack,
          style: TextButton.styleFrom(foregroundColor: context.foreground),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.color,
    required this.title,
    required this.body,
  });
  final int number;
  final Color color;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    final foreground = context.cardForeground(color);
    return MergeSemantics(
      child: HardCard(
        color: color,
        shadowOffset: const Offset(2, 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                // Step cards stay pastel in both themes, so the badge is ink.
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '$number',
                  style: OmniaText.label.copyWith(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    semanticsLabel: 'Step $number: $title',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(body, style: TextStyle(color: foreground, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
