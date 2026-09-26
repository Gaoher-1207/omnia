import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

/// A section title (announced as a heading), with optional supporting text
/// and a trailing action such as "See all".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.detail, this.action});
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            ?action,
          ],
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(detail!, style: TextStyle(color: context.mutedForeground)),
        ],
      ],
    ),
  );
}
