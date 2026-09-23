import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

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
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(time, style: const TextStyle(fontSize: 12)),
          ),
          CircleAvatar(
            radius: 14,
            backgroundColor: context.cardColor(color),
            child: Icon(icon, size: 16, color: context.foreground),
          ),
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
