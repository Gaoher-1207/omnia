import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: const [
      Text(
        'Insights',
        style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
      ),
      SizedBox(height: 5),
      Text('Patterns across your week  ·  SAMPLE DATA'),
      SizedBox(height: 24),
      HardCard(
        color: lilac,
        prominent: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OmniaMark(),
            SizedBox(height: 12),
            Text(
              'Your week in perspective',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text(
              'Insights will be connected to your real activity after '
              'tracking and the backend are ready.',
            ),
          ],
        ),
      ),
    ],
  );
}
