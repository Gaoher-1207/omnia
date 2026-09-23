import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';

class HardCard extends StatelessWidget {
  const HardCard({super.key, required this.color, required this.child});
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: ink, width: 1.6),
    ),
    child: child,
  );
}
