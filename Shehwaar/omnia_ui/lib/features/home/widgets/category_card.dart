import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/omnia_pressable.dart';

class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.amount,
    required this.goal,
    required this.color,
    required this.onTap,
    required this.dense,
  });
  final IconData icon;
  final String title, amount, goal;
  final Color color;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fill = context.cardColor(color);
    final foreground = context.cardForeground(color);
    return Semantics(
      button: true,
      child: SizedBox(
        height: dense ? 144 : null,
        child: OmniaPressable(
          radius: 12,
          shadowOffset: const Offset(2, 3),
          builder: (context, states) => Material(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              statesController: states,
              splashFactory: NoSplash.splashFactory,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(minHeight: 86),
                padding: EdgeInsets.all(dense ? 8 : 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: context.outlineOn(fill),
                    width: 1.6,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: foreground),
                  child: IconTheme.merge(
                    data: IconThemeData(color: foreground),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: dense ? 19 : 22),
                        const SizedBox(height: 5),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: dense ? 11 : 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          amount,
                          style: TextStyle(
                            fontSize: dense ? 13 : 17,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (goal.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            goal,
                            style: OmniaText.meta.copyWith(
                              fontSize: dense ? 11 : 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
