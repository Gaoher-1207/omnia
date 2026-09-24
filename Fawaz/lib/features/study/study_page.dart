import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/format.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/theme/surface_style.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/domain/revision_item.dart';
import 'package:omnia_ui/features/study/domain/study_plan.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';

enum _Section { plan, topics, exams, subjects }

class _StudyData {
  const _StudyData(this.subjects, this.topics, this.exams, this.plan);
  final List<Subject> subjects;
  final List<RevisionItem> topics;
  final List<Exam> exams;
  final StudyPlan plan;
}

const _subjectColors = ['#5B6CFF', '#E0892B', '#1F9D7A', '#D94F70', '#8A5CF6', '#2B8FD6'];

/// Subjects, exams, backlog/revision topics and the 7-day study plan.
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});
  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  late final deps = AppDependenciesScope.of(context);
  late final data = Loadable<_StudyData>(_load)..load();
  var _section = _Section.plan;
  bool _changed = false;

  Future<_StudyData> _load() async {
    final study = deps.study;
    final results = await Future.wait<Object>([
      study.getSubjects(),
      study.getTopics(),
      study.getExams(),
      study.getPlan(),
    ]);
    return _StudyData(
      results[0] as List<Subject>,
      results[1] as List<RevisionItem>,
      results[2] as List<Exam>,
      results[3] as StudyPlan,
    );
  }

  @override
  void dispose() {
    data.dispose();
    super.dispose();
  }

  Future<void> _mutate(Future<void> Function() action) async {
    try {
      await action();
      _changed = true;
      await data.load();
    } on ApiException catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop && _changed) SessionScope.refreshDashboard(context);
    },
    child: Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        title: const Text('Study', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: data.load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _logSession,
        backgroundColor: context.actionBackground,
        foregroundColor: context.actionForeground,
        icon: const Icon(Icons.timer_outlined),
        label: const Text('Log study', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: data,
          builder: (context, _) {
            final value = data.data;
            if (value == null) {
              return data.error == null ? const LoadingView() : ErrorView(error: data.error!, onRetry: data.load);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
              children: [
                _switcher(context),
                const SizedBox(height: 18),
                ...switch (_section) {
                  _Section.plan => _plan(value),
                  _Section.topics => _topics(value),
                  _Section.exams => _exams(value),
                  _Section.subjects => _subjects(value),
                },
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _switcher(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: SurfaceStyle.of(context).decoration(
      color: context.colors.surfaceContainerHighest,
      radius: 12,
      offset: const Offset(2, 2),
    ),
    child: Row(
      children: [
        for (final (section, name) in [
          (_Section.plan, 'Plan'),
          (_Section.topics, 'Topics'),
          (_Section.exams, 'Exams'),
          (_Section.subjects, 'Subjects'),
        ])
          Expanded(
            child: Material(
              color: _section == section ? context.cardColor(lilac) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => setState(() => _section = section),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _section == section ? context.cardForeground(lilac) : context.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  List<Widget> _plan(_StudyData value) {
    if (value.subjects.isEmpty) {
      return [
        MessageView(
          title: 'Add your subjects first',
          detail: 'Then add exams and topics, and your week of study fills in automatically.',
          action: SolidAction(label: 'Add a subject', onTap: () => setState(() => _section = _Section.subjects)),
        ),
      ];
    }
    return [
      for (final warning in value.plan.warnings)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HardCard(color: yellow, shadowOffset: const Offset(2, 2), child: Text(warning)),
        ),
      for (final day in value.plan.days) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                longDate(day.date),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${hoursLabel(day.plannedMinutes)} of ${hoursLabel(day.availableMinutes)}',
              style: TextStyle(fontSize: 12, color: context.mutedForeground),
            ),
          ],
        ),
        for (final exam in day.exams)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('📅 $exam', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        const SizedBox(height: 6),
        if (day.blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              day.availableMinutes == 0 ? 'Goal already met.' : 'Free: nothing pending.',
              style: TextStyle(color: context.mutedForeground),
            ),
          )
        else ...[
          for (final block in day.blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HardCard(
                color: blue,
                shadowOffset: const Offset(2, 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 58,
                      child: Text(hoursLabel(block.minutes), style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(block.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('${block.subjectName} · ${block.reason}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
      if (value.plan.unscheduledMinutes > 0)
        Text(
          '${hoursLabel(value.plan.unscheduledMinutes)} of topics are scheduled after this week.',
          style: TextStyle(color: context.mutedForeground, fontSize: 12),
        ),
    ];
  }

  List<Widget> _topics(_StudyData value) => [
    SolidAction(
      label: 'Add a topic',
      onTap: value.subjects.isEmpty
          ? () => setState(() => _section = _Section.subjects)
          : () => _addTopic(value.subjects),
    ),
    const SizedBox(height: 14),
    if (value.topics.isEmpty)
      const MessageView(title: 'No topics yet', detail: 'Add chapters you still need to cover or revise.')
    else
      for (final topic in value.topics)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HardCard(
            shadowOffset: const Offset(2, 3),
            color: topic.completed ? paper : blue,
            child: Row(
              children: [
                Checkbox(
                  value: topic.completed,
                  onChanged: (v) => _mutate(() => deps.study.setTopicDone(topic.id, v ?? false)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          decoration: topic.completed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      Text(
                        '${topic.subjectName ?? ''} · ${topic.isRevision ? 'Revision' : 'Backlog'} · '
                        '${hoursLabel(topic.estimatedMinutes)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete topic',
                  onPressed: () => _confirm('Delete “${topic.title}”?', () => deps.study.deleteTopic(topic.id)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
  ];

  List<Widget> _exams(_StudyData value) => [
    SolidAction(
      label: 'Add an exam',
      onTap: value.subjects.isEmpty
          ? () => setState(() => _section = _Section.subjects)
          : () => _addExam(value.subjects),
    ),
    const SizedBox(height: 14),
    if (value.exams.isEmpty)
      const MessageView(title: 'No upcoming exams', detail: 'Add your timetable so the planner can prioritise.')
    else
      for (final exam in value.exams)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HardCard(
            shadowOffset: const Offset(2, 3),
            color: (exam.daysLeft ?? 99) <= 7 ? lilac : paper,
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  child: Column(
                    children: [
                      Text('${exam.daysLeft ?? '–'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      Text(exam.daysLeft == 1 ? 'day' : 'days', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exam.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${exam.subjectName ?? ''} · ${longDate(exam.scheduledAt)}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete exam',
                  onPressed: () => _confirm('Delete “${exam.title}”?', () => deps.study.deleteExam(exam.id)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
  ];

  List<Widget> _subjects(_StudyData value) => [
    SolidAction(label: 'Add a subject', onTap: () => _addSubject(value.subjects.length)),
    const SizedBox(height: 14),
    if (value.subjects.isEmpty)
      const MessageView(title: 'No subjects yet', detail: 'Add the subjects you’re studying this term.')
    else
      for (final subject in value.subjects)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HardCard(
            shadowOffset: const Offset(2, 3),
            color: paper,
            child: Row(
              children: [
                const Icon(Icons.menu_book_outlined),
                const SizedBox(width: 10),
                Expanded(child: Text(subject.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                IconButton(
                  tooltip: 'Delete subject',
                  onPressed: () => _confirm(
                    'Delete “${subject.name}”? Its exams and topics are deleted too. Logged study time is kept.',
                    () => deps.study.deleteSubject(subject.id),
                  ),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
  ];

  Future<void> _confirm(String message, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Are you sure?'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _mutate(action);
  }

  Future<void> _addSubject(int count) async {
    final name = await _askText('Add a subject', 'Subject name', maxLength: 60);
    if (name == null) return;
    await _mutate(() => deps.study.createSubject(name, color: _subjectColors[count % _subjectColors.length]));
  }

  Future<void> _addTopic(List<Subject> subjects) async {
    final result = await showDialog<_TopicInput>(
      context: context,
      builder: (_) => _TopicDialog(subjects: subjects),
    );
    if (result == null) return;
    await _mutate(
      () => deps.study.createTopic(
        subjectId: result.subjectId,
        title: result.title,
        revision: result.revision,
        minutes: result.minutes,
      ),
    );
  }

  Future<void> _addExam(List<Subject> subjects) async {
    final result = await showDialog<_ExamInput>(
      context: context,
      builder: (_) => _ExamDialog(subjects: subjects),
    );
    if (result == null) return;
    await _mutate(() => deps.study.createExam(subjectId: result.subjectId, title: result.title, date: result.date));
  }

  Future<void> _logSession() async {
    final subjects = data.data?.subjects ?? const <Subject>[];
    final result = await showDialog<_LogInput>(
      context: context,
      builder: (_) => _LogDialog(subjects: subjects),
    );
    if (result == null) return;
    await _mutate(() => deps.study.logSession(minutes: result.minutes, subjectId: result.subjectId));
    if (mounted) showDone(context, 'Logged ${hoursLabel(result.minutes)} of study.');
  }

  Future<String?> _askText(String title, String label, {int maxLength = 120}) => showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(title: title, label: label, maxLength: maxLength),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.label, required this.maxLength});
  final String title, label;
  final int maxLength;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final text = _controller.text.trim();
    Navigator.pop(context, text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _done, child: const Text('Save')),
    ],
  );
}

class _TopicInput {
  const _TopicInput(this.subjectId, this.title, this.revision, this.minutes);
  final String subjectId, title;
  final bool revision;
  final int minutes;
}

class _ExamInput {
  const _ExamInput(this.subjectId, this.title, this.date);
  final String subjectId, title;
  final DateTime date;
}

class _LogInput {
  const _LogInput(this.subjectId, this.minutes);
  final String? subjectId;
  final int minutes;
}

Widget _subjectField(List<Subject> subjects, String? value, ValueChanged<String?> onChanged, {bool optional = false}) =>
    DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Subject'),
      items: [
        if (optional) const DropdownMenuItem<String>(value: null, child: Text('No subject')),
        for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name)),
      ],
      validator: (v) => !optional && v == null ? 'Choose a subject' : null,
      onChanged: onChanged,
    );

class _TopicDialog extends StatefulWidget {
  const _TopicDialog({required this.subjects});
  final List<Subject> subjects;
  @override
  State<_TopicDialog> createState() => _TopicDialogState();
}

class _TopicDialogState extends State<_TopicDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _minutes = TextEditingController(text: '60');
  late String? _subject = widget.subjects.first.id;
  bool _revision = false;

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a topic'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _subjectField(widget.subjects, _subject, (v) => setState(() => _subject = v)),
            TextFormField(
              controller: _title,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Topic', hintText: 'e.g. Chapter 5: Thermodynamics'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter a topic' : null,
            ),
            TextFormField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Estimated minutes'),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                return n == null || n < 5 || n > 600 ? '5 to 600 minutes' : null;
              },
            ),
            SwitchListTile(
              value: _revision,
              onChanged: (v) => setState(() => _revision = v),
              title: const Text('Revision (already studied once)'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              _TopicInput(_subject!, _title.text.trim(), _revision, int.parse(_minutes.text.trim())),
            );
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _ExamDialog extends StatefulWidget {
  const _ExamDialog({required this.subjects});
  final List<Subject> subjects;
  @override
  State<_ExamDialog> createState() => _ExamDialogState();
}

class _ExamDialogState extends State<_ExamDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  late String? _subject = widget.subjects.first.id;
  DateTime? _date;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add an exam'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _subjectField(widget.subjects, _subject, (v) => setState(() => _subject = v)),
          TextFormField(
            controller: _title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Exam', hintText: 'e.g. Semester final'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Enter a name' : null,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _date ?? now,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 3),
              );
              if (picked != null) setState(() => _date = picked);
            },
            icon: const Icon(Icons.event_outlined),
            label: Text(_date == null ? 'Pick the date' : longDate(_date!)),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate() && _date != null) {
            Navigator.pop(context, _ExamInput(_subject!, _title.text.trim(), _date!));
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _LogDialog extends StatefulWidget {
  const _LogDialog({required this.subjects});
  final List<Subject> subjects;
  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  final _form = GlobalKey<FormState>();
  final _minutes = TextEditingController(text: '45');
  String? _subject;

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Log study time'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _subjectField(widget.subjects, _subject, (v) => setState(() => _subject = v), optional: true),
          TextFormField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Minutes studied today'),
            validator: (v) {
              final n = int.tryParse(v?.trim() ?? '');
              return n == null || n < 1 || n > 720 ? '1 to 720 minutes' : null;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _LogInput(_subject, int.parse(_minutes.text.trim())));
          }
        },
        child: const Text('Log'),
      ),
    ],
  );
}
