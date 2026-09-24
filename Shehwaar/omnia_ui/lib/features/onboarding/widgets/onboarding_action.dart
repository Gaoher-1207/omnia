import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/surface_shadow.dart';

/// The full-width primary onboarding button (label plus trailing arrow).
class OnboardingAction extends StatelessWidget {
  const OnboardingAction({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SurfaceShadow(
      radius: 9,
      offset: const Offset(2, 2),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: context.actionBackground,
          foregroundColor: context.actionForeground,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.arrow_forward),
          ],
        ),
      ),
    ),
  );
}
