import 'package:flutter/material.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';

Future<void> editRevision(
  BuildContext context,
  RevisionController revision,
) async {
  final title = await showDialog<String>(
    context: context,
    builder: (_) => _EditRevisionDialog(title: revision.title),
  );
  if (title != null) revision.rename(title);
}

class _EditRevisionDialog extends StatefulWidget {
  const _EditRevisionDialog({required this.title});
  final String title;
  @override
  State<_EditRevisionDialog> createState() => _EditRevisionDialogState();
}

class _EditRevisionDialogState extends State<_EditRevisionDialog> {
  late final controller = TextEditingController(text: widget.title);
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
    title: const Text('Edit revision'),
    content: Form(
      key: form,
      child: TextFormField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(labelText: 'Title'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Enter a title' : null,
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
