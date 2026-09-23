import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/surface_shadow.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

class SolidAction extends StatelessWidget {
  const SolidAction({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SurfaceShadow(
    radius: 9,
    offset: const Offset(2, 2),
    child: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: context.actionBackground,
        foregroundColor: context.actionForeground,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
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
