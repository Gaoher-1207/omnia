import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/omnia_progress_bar.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';

/// One area on the Areas hub: its name, a real status and, when it has a
/// daily target, progress towards it. A tap opens the area.
class AreaTile extends StatelessWidget {
  const AreaTile({
    super.key,
    required this.icon,
    required this.name,
    required this.amount,
    required this.goal,
    required this.color,
    required this.onTap,
    this.progress,
  });
  final IconData icon;
  final String name, amount, goal;
  final Color color;
  final VoidCallback onTap;

  /// Null when the area has no daily target to measure against.
  final double? progress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: HardCard(
      color: color,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            amount,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          if (goal.isNotEmpty) Text(goal, style: OmniaText.meta),
          if (progress != null) ...[
            const SizedBox(height: 10),
            OmniaProgressBar(
              value: progress!,
              color: color,
              height: 8,
              radius: 8,
              semanticsLabel: '$name progress',
            ),
          ],
        ],
      ),
    ),
  );
}
