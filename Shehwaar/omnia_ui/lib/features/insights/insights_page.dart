import 'package:flutter/material.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';

/// Patterns over time. Nothing is computed yet, so it says so rather than
/// drawing charts from invented numbers.
class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
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
        AppDependenciesScope.of(context).sampleContent
            ? 'Patterns across your week  ·  SAMPLE DATA'
            : 'Patterns across your week',
        style: TextStyle(color: context.mutedForeground),
      ),
      const SizedBox(height: 24),
      const HardCard(
        color: lilac,
        prominent: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OmniaMark(),
            SizedBox(height: 12),
            Text(
              'No insights yet',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text(
              'Insights aren’t connected yet. They’ll build on the '
              'activity, sleep and study you log.',
            ),
          ],
        ),
      ),
    ],
  );
}
