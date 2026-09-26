import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';

/// A centred title, optional detail and optional action, in the same style
/// as the Tasks and Goals empty/error states.
class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.title, this.detail, this.action});
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.mutedForeground),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

/// Nothing here yet, inside a page: a plain card saying so, with an optional
/// next step. Never a stand-in for data that is still loading.
class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.title,
    this.detail,
    this.action,
    this.onTap,
  });
  final String title;
  final String? detail;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => HardCard(
    color: paper,
    shadowOffset: const Offset(2, 3),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail!, style: TextStyle(color: context.mutedForeground)),
        ],
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.title,
  });
  final Object error;
  final VoidCallback onRetry;
  final String? title;

  @override
  Widget build(BuildContext context) => MessageView(
    title: title ?? "Couldn't load this",
    detail: friendlyError(error),
    action: SolidAction(label: 'Try again', onTap: onRetry),
  );
}

/// A floating message for a failed action (save, delete…).
void showError(BuildContext context, Object error) =>
    showDone(context, friendlyError(error));

/// Replaces any message still showing, so the latest outcome is never queued
/// behind an older one.
void showDone(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
