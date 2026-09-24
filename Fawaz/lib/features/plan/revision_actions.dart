import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';

/// Add a topic to this subject; it's saved as a revision item on the backend.
Future<void> addRevisionTopic(
  BuildContext context,
  RevisionController revision,
) async {
  final title = await showDialog<String>(
    context: context,
    builder: (_) => const _TopicDialog(),
  );
  if (title == null || !context.mounted) return;
  if (!await revision.addTopic(title) && context.mounted) {
    showDone(context, "Couldn't add that topic. Try again.");
  }
}

class _TopicDialog extends StatefulWidget {
  const _TopicDialog();
  @override
  State<_TopicDialog> createState() => _TopicDialogState();
}

class _TopicDialogState extends State<_TopicDialog> {
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void save() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a topic'),
    content: Form(
      key: form,
      child: TextFormField(
        controller: controller,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Topic'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Enter a topic' : null,
        onFieldSubmitted: (_) => save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: save, child: const Text('Save')),
    ],
  );
}
