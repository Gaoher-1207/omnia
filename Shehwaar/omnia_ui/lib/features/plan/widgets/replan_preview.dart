import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/widgets/action_row.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/plan/plan_controller.dart';
import 'package:omnia_ui/features/plan/replan_change_format.dart';

/// Asks the backend for a validated proposal for [request] and shows it as
/// a compact preview. Nothing changes unless the user taps Apply; closing
/// the preview any other way dismisses the proposal. Used by Plan's "Adjust
/// today's plan" and by Ask Omnia.
Future<void> previewReplan(
  BuildContext context,
  PlanController controller,
  String request,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final created = await controller.createReplanProposal(request);
  if (!context.mounted) return;
  if (!created) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          friendlyError(controller.replanError ?? StateError('failed')),
        ),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: ReplanPreviewSheet(controller: controller),
    ),
  );
  // A preview closed without Apply or Cancel is still discarded server-side.
  if (controller.replanProposal != null) {
    await controller.dismissReplanProposal();
  }
  final notice = controller.replanNotice;
  if (notice != null) {
    messenger.showSnackBar(SnackBar(content: Text(notice)));
    controller.clearReplanNotice();
  }
}

/// A compact preview: one action-and-title line per change, then Apply or Cancel.
/// Proposal internals (summary, reasons, schedule, validation) stay hidden.
class ReplanPreviewSheet extends StatelessWidget {
  const ReplanPreviewSheet({super.key, required this.controller});

  final PlanController controller;

  Future<void> _apply(BuildContext context) async {
    final applied = await controller.applyReplanProposal();
    if (context.mounted && (applied || controller.replanProposal == null)) {
      Navigator.pop(context);
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final dismissed = await controller.dismissReplanProposal();
    if (context.mounted && dismissed) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final proposal = controller.replanProposal;
      if (proposal == null) return const SizedBox.shrink();
      final changes = describeReplanChanges(proposal.operations);
      final busy = controller.proposalActionBusy;
      final error = controller.replanError;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Semantics(
            header: true,
            child: const Text(
              'Plan changes',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 12),
          if (changes.isEmpty)
            const Text('No changes needed.')
          else
            for (final change in changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ExcludeSemantics(child: Text('•  ')),
                    Expanded(child: Text(change)),
                  ],
                ),
              ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                friendlyError(error),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          if (busy) ...[
            const LinearProgressIndicator(semanticsLabel: 'Updating plan'),
            const SizedBox(height: 12),
          ],
          AbsorbPointer(
            absorbing: busy,
            child: changes.isEmpty
                ? SizedBox(
                    width: double.infinity,
                    child: OutlineAction(
                      icon: Icons.close,
                      label: 'Close',
                      onPressed: () => _cancel(context),
                    ),
                  )
                : ActionRow(
                    primary: SolidAction(
                      label: 'Apply',
                      onTap: () => _apply(context),
                    ),
                    secondary: [
                      OutlineAction(
                        icon: Icons.close,
                        label: 'Cancel',
                        onPressed: () => _cancel(context),
                      ),
                    ],
                  ),
          ),
        ],
      );
    },
  );
}
