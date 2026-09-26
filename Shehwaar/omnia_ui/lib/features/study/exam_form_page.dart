import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/widgets/select_field.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/home/dashboard_format.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/study_controller.dart';
import 'package:omnia_ui/features/study/subject_form_page.dart';
import 'package:omnia_ui/features/study/widgets/exam_card.dart';

/// Add an exam (initial == null) or change one. The subject is picked from
/// the user's subjects, never retyped; with none yet, the form offers to
/// add one first. Exams are whole days: the backend stores no time.
class ExamFormPage extends StatefulWidget {
  const ExamFormPage({super.key, this.initial, this.subjectId});
  final Exam? initial;

  /// Preselected subject for a new exam (e.g. from a subject's page).
  final String? subjectId;

  static Future<Exam?> open(
    BuildContext context, {
    Exam? initial,
    String? subjectId,
  }) => Navigator.of(context, rootNavigator: true).push<Exam>(
    MaterialPageRoute(
      builder: (_) => ExamFormPage(initial: initial, subjectId: subjectId),
    ),
  );

  @override
  State<ExamFormPage> createState() => _ExamFormPageState();
}

class _ExamFormPageState extends State<ExamFormPage> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _notes = TextEditingController(text: widget.initial?.notes);
  late String? _subjectId = widget.initial?.subjectId ?? widget.subjectId;
  late DateTime? _date = widget.initial?.date;
  ApiException? _error;
  bool _saving = false, _dateMissing = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The server's today (upcoming exams start there), else the device's.
  DateTime get _today {
    final server = DashboardScope.read(context).dashboard?.date;
    final now = DateTime.now();
    return server ?? DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _dateMissing = false;
      });
    }
  }

  Future<void> _addSubject() async {
    final subject = await SubjectFormPage.open(context);
    if (subject != null && mounted) setState(() => _subjectId = subject.id);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (StudyScope.read(context).subjects.isEmpty) {
      showDone(context, 'Add a subject first.');
      return;
    }
    setState(() {
      _error = null;
      _dateMissing = _date == null;
    });
    if (!_form.currentState!.validate() || _date == null) return;
    final notes = _notes.text.trim();
    final draft = ExamDraft(
      subjectId: _subjectId!,
      title: _title.text.trim(),
      date: _date!,
      notes: notes.isEmpty ? null : notes,
    );
    final study = StudyScope.read(context);
    final initial = widget.initial;
    setState(() => _saving = true);
    final Exam? saved;
    try {
      saved = initial == null
          ? await study.createExam(draft)
          : await study.updateExam(initial.id, draft);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
      showError(context, error);
      // The subject or exam may have been deleted elsewhere.
      if (error.isNotFound) study.load();
      return;
    }
    if (!mounted) return;
    if (saved == null) {
      setState(() => _saving = false);
      return;
    }
    showDone(
      context,
      studySavedMessage(
        initial == null ? 'Exam added' : 'Exam saved',
        todayStale: DashboardScope.read(context).loadError != null,
      ),
    );
    Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final study = StudyScope.of(context);
    final subjects = study.subjects;
    final error = _error;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New exam' : 'Edit exam'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (subjects.isEmpty)
              EmptyCard(
                title: 'Add a subject first.',
                detail: 'Every exam belongs to one of your subjects.',
                action: SolidAction(label: 'New subject', onTap: _addSubject),
              )
            else ...[
              // Rebuilt when a subject is added from here, so it shows it.
              SelectField<String?>(
                key: ValueKey(_subjectId),
                label: 'Subject',
                initialValue: _subjectId,
                errorText: error?.fieldMessage('subject_id'),
                options: [
                  for (final subject in subjects)
                    SelectOption(subject.id, subject.name),
                ],
                validator: (value) => value == null ? 'Choose a subject' : null,
                onChanged: (value) => setState(() => _subjectId = value),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _addSubject,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New subject'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextFormField(
              controller: _title,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Exam',
                hintText: 'e.g. Midterm, Final, Unit test 2',
                errorText: error?.fieldMessage('title'),
                errorMaxLines: 3,
              ),
              validator: (text) =>
                  (text ?? '').trim().isEmpty ? 'Enter the exam' : null,
            ),
            const SizedBox(height: 8),
            PickerField(
              label: 'Date',
              value: _date == null ? null : formatLongDate(_date!),
              icon: Icons.event_outlined,
              onTap: _pickDate,
              errorText: _dateMissing
                  ? 'Choose the exam date'
                  : error?.fieldMessage('exam_date'),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                errorText: error?.fieldMessage('notes'),
              ),
            ),
            const SizedBox(height: 24),
            SolidAction(label: _saving ? 'Saving…' : 'Save', onTap: _save),
          ],
        ),
      ),
    );
  }
}
