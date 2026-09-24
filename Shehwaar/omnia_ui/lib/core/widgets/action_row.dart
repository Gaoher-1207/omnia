import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

/// A primary action followed by compact secondary actions on one line. At
/// large accessibility text sizes the primary takes its own full-width line
/// and the secondaries share the next, so no label is squeezed or clipped.
class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.primary, required this.secondary});
  final Widget primary;
  final List<Widget> secondary;

  @override
  Widget build(BuildContext context) {
    final secondaries = [
      for (final (i, action) in secondary.indexed) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: action),
      ],
    ];
    if (MediaQuery.textScalerOf(context).scale(14) <= 14 * 1.3) {
      return Row(
        children: [
          Expanded(child: primary),
          const SizedBox(width: 8),
          ...secondaries,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        primary,
        const SizedBox(height: 8),
        Row(children: secondaries),
      ],
    );
  }
}

/// The outlined secondary button used beside a [SolidAction].
class OutlineAction extends StatelessWidget {
  const OutlineAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: context.foreground,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
      side: BorderSide(color: context.outline, width: 1.5),
    ),
  );
}
