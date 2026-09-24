import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/surface_shadow.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

class HardCard extends StatelessWidget {
  const HardCard({
    super.key,
    required this.color,
    required this.child,
    this.onTap,
    this.prominent = false,
    this.shadowOffset = const Offset(3, 4),
  });
  final Color color;
  final bool prominent;
  final Widget child;
  final Offset shadowOffset;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SurfaceShadow(
    radius: 14,
    offset: shadowOffset,
    child: Material(
      color: context.cardColor(color, prominent: prominent),
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
          child: context.isDark
              ? DefaultTextStyle.merge(
                  style: TextStyle(
                    color: context.cardForeground(color, prominent: prominent),
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: context.cardForeground(
                        color,
                        prominent: prominent,
                      ),
                    ),
                    child: child,
                  ),
                )
              : child,
        ),
      ),
    ),
  );
}
