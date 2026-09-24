import 'package:flutter/material.dart';

class ActivityLine extends StatelessWidget {
  const ActivityLine({
    super.key,
    required this.icon,
    required this.title,
    required this.time,
  });
  final IconData icon;
  final String title, time;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 9),
        Expanded(child: Text(title)),
        Text(time, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}
