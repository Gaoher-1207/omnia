import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

/// A small category-coloured circle (optionally holding an icon) with an
/// outline and a 1px unblurred offset so it separates from its background.
class AccentCircle extends StatelessWidget {
  const AccentCircle({
    super.key,
    required this.color,
    required this.size,
    this.icon,
  });
  final Color color;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fill = context.cardColor(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(
          color: context.outlineOn(fill),
          width: size < 16 ? 1 : 1.4,
        ),
        boxShadow: const [BoxShadow(color: ink, offset: Offset(1, 1))],
      ),
      child: icon == null
          ? null
          : Icon(icon, size: size * .57, color: context.cardForeground(color)),
    );
  }
}
