import 'package:flutter/material.dart';
import 'package:omnia_ui/features/focus/focus_timer_page.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/info_dialog.dart';
import 'package:omnia_ui/features/plan/revision_controller.dart';
import 'package:omnia_ui/features/plan/revision_actions.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';

class RevisionDetailPage extends StatelessWidget {
  const RevisionDetailPage({super.key});
  @override
  Widget build(BuildContext context) {
    final revision = RevisionScope.of(context);
    final tasks = revision.tasks;
    final done = revision.done;
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        title: Text(
          revision.title,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const HardCard(
                  shadowOffset: Offset(1, 1),
                  color: blue,
                  child: Icon(Icons.menu_book_outlined, size: 32),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        revision.title,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text('Tue, Sep 23  ·  10:00 – 10:45'),
                      Text(
                        '45 minutes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SolidAction(
                    label: done == tasks.length ? 'Completed' : 'Mark done',
                    onTap: () => revision.markAll(done != tasks.length),
                  ),
                ),
                const SizedBox(width: 8),
                _smallAction(
                  context,
                  Icons.edit_outlined,
                  'Edit',
                  () => editRevision(context, revision),
                ),
                const SizedBox(width: 8),
                _smallAction(
                  context,
                  Icons.more_horiz,
                  'More',
                  () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Revision actions'),
                      content: const Text('Reset all sub-tasks to incomplete?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            revision.markAll(false);
                            Navigator.pop(context);
                          },
                          child: const Text('Reset sub-tasks'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            HardCard(
              color: lilac,
              prominent: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      OmniaMark(),
                      SizedBox(width: 8),
                      Text(
                        'omnia recommends',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Keep this revision session short so you have time '
                    'for the rest of your plan.',
                    style: TextStyle(height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      border: Border.all(color: context.outline),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        color: context.isDark ? context.foreground : null,
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'What changed?',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'This is sample copy. The AI explanation will be '
                            'connected when that service is ready.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Materials',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 9),
            HardCard(
              onTap: () => showInfoDialog(
                context,
                'Sample material',
                'Coming soon. DBMS Notes.pdf is sample text; no file is attached yet.',
              ),
              color: paper,
              child: Row(
                children: [
                  Icon(Icons.description_outlined),
                  SizedBox(width: 10),
                  Expanded(child: Text('DBMS Notes.pdf  ·  Sample')),
                  Icon(Icons.more_vert),
                ],
              ),
            ),
            const SizedBox(height: 19),
            Text(
              'Sub-tasks  $done/${tasks.length}',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            for (var i = 0; i < tasks.length; i++)
              CheckboxListTile(
                value: revision.isChecked(i),
                activeColor: context.colors.primary,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tasks[i],
                  style: TextStyle(
                    decoration: revision.isChecked(i)
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                onChanged: (value) => revision.setChecked(i, value ?? false),
              ),
            const SizedBox(height: 15),
            SolidAction(
              label: 'Start Focus Session',
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const FocusTimerPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallAction(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onPressed,
  ) => Expanded(
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(title),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.foreground,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
        side: BorderSide(color: context.outline, width: 1.5),
      ),
    ),
  );
}
