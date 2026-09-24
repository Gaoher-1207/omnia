import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

/// Linear progress on an accent card, outlined with the theme outline
/// (ink in light mode, the high-contrast outline in dark mode).
class OmniaProgressBar extends StatelessWidget {
  const OmniaProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 7,
    this.radius = 9,
  });
  final double value;
  final Color color;
  final double height, radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: context.outlineOn(context.cardColor(color)),
        width: 1.2,
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: context.progressTrack(color),
        color: context.cardForeground(color),
      ),
    ),
  );
}
