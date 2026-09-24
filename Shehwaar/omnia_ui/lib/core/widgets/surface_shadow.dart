import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/surface_style.dart';

/// Adds a solid offset layer behind an already-painted, rounded surface.
class SurfaceShadow extends StatelessWidget {
  const SurfaceShadow({
    super.key,
    required this.child,
    required this.radius,
    this.offset = const Offset(3, 4),
  });
  final Widget child;
  final double radius;
  final Offset offset;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: SurfaceStyle.of(context)
        .decoration(radius: radius, offset: offset, border: false),
    child: child,
  );
}
