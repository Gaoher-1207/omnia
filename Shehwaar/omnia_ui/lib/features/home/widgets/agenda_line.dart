import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/accent_circle.dart';

class AgendaLine extends StatelessWidget {
  const AgendaLine({
    super.key,
    required this.time,
    required this.title,
    required this.duration,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String time, title, duration;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    // A 48dp minimum keeps each agenda item an easy tap target.
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(time, style: const TextStyle(fontSize: 12)),
          ),
          AccentCircle(color: color, size: 28, icon: icon),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(duration, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
