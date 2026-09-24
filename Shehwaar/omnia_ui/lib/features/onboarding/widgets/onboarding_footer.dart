import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

class OnboardingFooter extends StatelessWidget {
  const OnboardingFooter({
    super.key,
    required this.pageIndex,
    required this.pageCount,
  });
  final int pageIndex, pageCount;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Semantics(
        label: 'Onboarding page ${pageIndex + 1} of $pageCount',
        child: Row(
          children: [
            for (var index = 0; index < pageCount; index++)
              Container(
                width: index == pageIndex ? 24 : 7,
                height: 7,
                margin: const EdgeInsets.only(right: 7),
                decoration: BoxDecoration(
                  color: index == pageIndex
                      ? context.foreground
                      : context.mutedForeground.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Text(
          'NOT JUST A PLANNER.\nA CALMER, MORE\nINTENTIONAL YOU.',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: context.mutedForeground,
            fontSize: 11,
            height: 1.4,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
          ),
        ),
      ),
    ],
  );
}
