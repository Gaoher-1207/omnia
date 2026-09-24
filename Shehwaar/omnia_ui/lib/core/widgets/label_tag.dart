import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';

class LabelTag extends StatelessWidget {
  const LabelTag({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: context.actionBackground,
      border: Border.all(color: context.outlineOn(context.actionBackground)),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: context.actionForeground,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}
