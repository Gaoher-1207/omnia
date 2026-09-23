import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/features/plan/revision_detail_page.dart';
import 'package:omnia_ui/features/plan/widgets/timeline_row.dart';

class PlanPage extends StatelessWidget {
  const PlanPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const Center(
        child: Text(
          "Today's Plan",
          style: TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 4),
      const Center(
        child: Text(
          'Tue, Sep 23  ·  SAMPLE DAY',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF303238),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _mode('Timeline', true),
            _mode('List', false),
            _mode('Focus', false),
          ],
        ),
      ),
      const SizedBox(height: 21),
      const TimelineRow(
        time: '08:00',
        title: 'Morning Routine',
        duration: '30m',
        icon: Icons.dark_mode_outlined,
        color: lilac,
      ),
      const TimelineRow(
        time: '09:00',
        title: 'College / Classes',
        duration: '1h',
        icon: Icons.school_outlined,
        color: yellow,
      ),
      TimelineRow(
        time: '10:00',
        title: 'DBMS Revision',
        duration: '45m',
        icon: Icons.menu_book_outlined,
        color: blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RevisionDetailPage()),
        ),
      ),
      const TimelineRow(
        time: '11:00',
        title: 'Complete Assignment',
        duration: '1h',
        icon: Icons.task_alt,
        color: yellow,
      ),
      const TimelineRow(
        time: '13:00',
        title: 'Lunch',
        duration: '1h',
        icon: Icons.restaurant_outlined,
        color: mint,
      ),
      const TimelineRow(
        time: '16:30',
        title: 'Walk',
        duration: '20m',
        icon: Icons.directions_walk,
        color: mint,
      ),
      const TimelineRow(
        time: '18:30',
        title: 'Push Workout',
        duration: '35m',
        icon: Icons.fitness_center,
        color: mint,
      ),
      const TimelineRow(
        time: '21:00',
        title: 'Revision',
        duration: '45m',
        icon: Icons.menu_book_outlined,
        color: blue,
      ),
      const TimelineRow(
        time: '22:00',
        title: 'Wind Down',
        duration: '30m',
        icon: Icons.dark_mode_outlined,
        color: lilac,
      ),
      const SizedBox(height: 18),
      const HardCard(
        color: lilac,
        child: Row(
          children: [
            OmniaMark(),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                'Your plan will adapt as your day changes.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(Icons.arrow_forward),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Timeline is a visual sample. Scheduling and rescheduling '
        'will be connected when the planning API is ready.',
        style: TextStyle(color: Colors.white60, fontSize: 12),
      ),
    ],
  );
  Widget _mode(String name, bool selected) => Expanded(
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? lilac : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        name,
        style: TextStyle(
          color: selected ? ink : Colors.white70,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
