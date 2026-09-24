import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';

class OmniaMark extends StatelessWidget {
  const OmniaMark({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 34,
    child: Stack(
      children: [
        Positioned(
          left: 1,
          top: 8,
          child: _circle(22, purple.withValues(alpha: .65)),
        ),
        Positioned(
          left: 10,
          top: 1,
          child: _circle(22, const Color(0xFFAA92FF).withValues(alpha: .8)),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: _circle(20, const Color(0xFF4538D8).withValues(alpha: .75)),
        ),
      ],
    ),
  );
  Widget _circle(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}
