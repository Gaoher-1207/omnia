import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

class HardCard extends StatelessWidget {
  const HardCard({
    super.key,
    required this.color,
    required this.child,
    this.onTap,
  });
  final Color color;
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: context.cardColor(color),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.outline, width: 1.6),
        ),
        child: child,
      ),
    ),
  );
}
