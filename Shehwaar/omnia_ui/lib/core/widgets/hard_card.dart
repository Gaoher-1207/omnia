import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/omnia_pressable.dart';
import 'package:omnia_ui/core/widgets/surface_shadow.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

/// The app's bordered card. With [onTap] it is a control and presses into its
/// shadow ([OmniaPressable]); without one it is information and stays still.
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

  static const _radius = 14.0;

  @override
  Widget build(BuildContext context) => onTap == null
      ? SurfaceShadow(
          radius: _radius,
          offset: shadowOffset,
          child: _surface(context, null),
        )
      : OmniaPressable(
          radius: _radius,
          shadowOffset: shadowOffset,
          builder: _surface,
        );

  Widget _surface(
    BuildContext context,
    WidgetStatesController? states,
  ) => Material(
    color: context.cardColor(color, prominent: prominent),
    borderRadius: BorderRadius.circular(_radius),
    child: InkWell(
      onTap: onTap,
      statesController: states,
      // The press into the shadow is the feedback; no ripple on top.
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(_radius),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(
            color: context.outlineOn(
              context.cardColor(color, prominent: prominent),
            ),
            width: 1.6,
          ),
        ),
        child: context.isDark
            ? DefaultTextStyle.merge(
                style: TextStyle(
                  color: context.cardForeground(color, prominent: prominent),
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: context.cardForeground(color, prominent: prominent),
                  ),
                  child: child,
                ),
              )
            : child,
      ),
    ),
  );
}
