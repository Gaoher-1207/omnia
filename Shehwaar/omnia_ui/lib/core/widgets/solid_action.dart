import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/omnia_pressable.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

class SolidAction extends StatelessWidget {
  const SolidAction({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OmniaPressable(
    radius: 9,
    shadowOffset: const Offset(2, 2),
    builder: (context, states) => FilledButton(
      onPressed: onTap,
      statesController: states,
      style: FilledButton.styleFrom(
        backgroundColor: context.actionBackground,
        foregroundColor: context.actionForeground,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        // The press into the shadow is the feedback; no ripple on top.
        splashFactory: NoSplash.splashFactory,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  );
}
