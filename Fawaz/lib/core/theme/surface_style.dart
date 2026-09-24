import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';

/// Shared, unblurred physical layers. These paint outside the surface without
/// adding padding or changing its layout or hit target.
class SurfaceStyle {
  const SurfaceStyle(this.brightness);
  factory SurfaceStyle.of(BuildContext context) =>
      SurfaceStyle(Theme.of(context).brightness);

  final Brightness brightness;
  bool get _dark => brightness == Brightness.dark;
  Color get outline => _dark ? const Color(0xFFAAA1BC) : ink;
  Color get shadow => _dark ? darkOffsetShadow : ink;
  BorderSide get side => BorderSide(color: outline, width: 1.6);

  BoxDecoration decoration({
    required double radius,
    Color? color,
    Offset offset = const Offset(3, 4),
    bool border = true,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: border ? Border.fromBorderSide(side) : null,
    boxShadow: offset == Offset.zero
        ? null
        : [BoxShadow(color: shadow, offset: offset, blurRadius: 0)],
  );
}
