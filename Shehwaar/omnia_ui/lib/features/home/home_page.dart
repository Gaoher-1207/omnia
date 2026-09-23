import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/label_tag.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/home/widgets/agenda_line.dart';
import 'package:omnia_ui/features/home/widgets/category_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.openPlan});
  final VoidCallback openPlan;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Good morning,\nShew.',
              style: TextStyle(
                fontSize: 29,
                height: 1.04,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: () {},
            icon: const Icon(Icons.person_outline),
            style: IconButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      const Text(
        'Tuesday, September 23  ·  SAMPLE DAY',
        style: TextStyle(fontSize: 12, letterSpacing: .4, color: ink),
      ),
      const SizedBox(height: 18),
      HardCard(
        color: lilac,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                OmniaMark(),
                SizedBox(width: 9),
                Text(
                  'omnia',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                Spacer(),
                LabelTag(text: 'SAMPLE'),
              ],
            ),
            const SizedBox(height: 17),
            const Text(
              'Your DBMS exam is in 8 days.',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your plan includes a 45-minute revision session today. '
              'You can adjust it to fit your schedule.',
              style: TextStyle(height: 1.35),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SolidAction(
                    label: "View today's plan",
                    onTap: openPlan,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('This is a sample recommendation.'),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink,
                    side: const BorderSide(color: ink, width: 1.5),
                  ),
                  child: const Text('Why?'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      const Row(
        children: [
          Expanded(
            child: CategoryCard(
              icon: Icons.menu_book_outlined,
              title: 'Study',
              amount: '2h 15m',
              goal: '/ 4h',
              progress: .56,
              color: blue,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: CategoryCard(
              icon: Icons.task_alt,
              title: 'Tasks',
              amount: '4 / 6',
              goal: 'completed',
              progress: .67,
              color: yellow,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Row(
        children: [
          Expanded(
            child: CategoryCard(
              icon: Icons.directions_run,
              title: 'Activity',
              amount: '6,240',
              goal: '/ 8,000',
              progress: .78,
              color: mint,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: CategoryCard(
              icon: Icons.dark_mode_outlined,
              title: 'Sleep',
              amount: '6h 42m',
              goal: '/ 8h',
              progress: .84,
              color: lilac,
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Next up',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          TextButton(onPressed: openPlan, child: const Text('See all →')),
        ],
      ),
      const AgendaLine(
        time: '10:00',
        title: 'DBMS Revision',
        duration: '45m',
        icon: Icons.menu_book_outlined,
        color: blue,
      ),
      const AgendaLine(
        time: '11:00',
        title: 'Complete Assignment',
        duration: '1h',
        icon: Icons.task_alt,
        color: yellow,
      ),
      const AgendaLine(
        time: '16:30',
        title: 'Walk',
        duration: '20m',
        icon: Icons.directions_walk,
        color: mint,
      ),
      const SizedBox(height: 18),
    ],
  );
}
