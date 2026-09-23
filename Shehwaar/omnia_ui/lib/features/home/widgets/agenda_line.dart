import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';

class AgendaLine extends StatelessWidget {
  const AgendaLine({
    super.key,
    required this.time,
    required this.title,
    required this.duration,
    required this.icon,
    required this.color,
  });
  final String time, title, duration;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(time, style: const TextStyle(fontSize: 12)),
        ),
        CircleAvatar(
          radius: 14,
          backgroundColor: color,
          child: Icon(icon, size: 16, color: ink),
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
  );
}
