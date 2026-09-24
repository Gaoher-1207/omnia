import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';

class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.amount,
    required this.goal,
    required this.progress,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title, amount, goal;
  final double progress;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => HardCard(
    shadowOffset: const Offset(2, 3),
    onTap: onTap,
    color: color,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 27),
        const SizedBox(height: 5),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(
          amount,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        Text(goal, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: context.progressTrack(color),
            color: context.cardForeground(color),
          ),
        ),
      ],
    ),
  );
}
