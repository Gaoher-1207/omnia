import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';

// (left, top, diameter, colour) of the three overlapping circles.
const _circles = [
  (1.0, 8.0, 22.0, Color(0xA67666ED)), // purple @ .65
  (10.0, 1.0, 22.0, Color(0xCCAA92FF)),
  (12.0, 12.0, 20.0, Color(0xBF4538D8)),
];

class OmniaMark extends StatelessWidget {
  const OmniaMark({super.key, this.lifted = true});

  /// Adds a restrained 1.5px offset so the mark separates from coloured cards.
  /// Turn off where the mark is scaled up as standalone artwork.
  final bool lifted;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 34,
    child: CustomPaint(painter: _MarkPainter(lifted)),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.lifted);
  final bool lifted;

  static Path _union(Offset shift) {
    var path = Path();
    for (final (left, top, size, _) in _circles) {
      path = Path.combine(
        PathOperation.union,
        path,
        Path()..addOval(Rect.fromLTWH(left, top, size, size).shift(shift)),
      );
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (lifted) {
      // Only the sliver outside the mark, so the translucent artwork's
      // colours stay exactly as they were.
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          _union(const Offset(1.5, 1.5)),
          _union(Offset.zero),
        ),
        Paint()..color = ink.withValues(alpha: .55),
      );
    }
    for (final (left, top, diameter, color) in _circles) {
      final radius = diameter / 2;
      canvas.drawCircle(
        Offset(left + radius, top + radius),
        radius,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.lifted != lifted;
}
