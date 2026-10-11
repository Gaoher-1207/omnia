import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/omnia_pressable.dart';

/// A square icon control in the card language: a pastel fill, the theme's
/// hard outline and offset shadow, and a press that sinks into the shadow.
/// 48 × 48 so it is easy to hit; [tooltip] is also its screen-reader label.
class OmniaIconButton extends StatelessWidget {
  const OmniaIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = lilac,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// One of the card accents; mapped to its dark-mode family.
  final Color color;

  static const size = 48.0, radius = 12.0;

  @override
  Widget build(BuildContext context) {
    final fill = context.cardColor(color);
    final foreground = context.cardForeground(color);
    return OmniaPressable(
      radius: radius,
      shadowOffset: const Offset(2, 3),
      builder: (context, states) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        statesController: states,
        icon: Icon(icon, size: 24),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(size),
          minimumSize: const Size.square(size),
          backgroundColor: fill,
          foregroundColor: foreground,
          // The press into the shadow is the feedback; no ripple on top.
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(color: context.outlineOn(fill), width: 1.6),
          ),
        ),
      ),
    );
  }
}
