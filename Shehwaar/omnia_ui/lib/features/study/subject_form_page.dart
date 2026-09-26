import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/home/dashboard_controller.dart';
import 'package:omnia_ui/features/study/domain/subject.dart';
import 'package:omnia_ui/features/study/study_controller.dart';
import 'package:omnia_ui/features/study/widgets/exam_card.dart';

/// Add a subject (initial == null) or rename one. Pops with the stored
/// subject; a refusal keeps the typed name and says why under the field.
class SubjectFormPage extends StatefulWidget {
  const SubjectFormPage({super.key, this.initial});
  final Subject? initial;

  /// A short form: it takes the whole screen, over the tab bar.
  static Future<Subject?> open(BuildContext context, {Subject? initial}) =>
      Navigator.of(context, rootNavigator: true).push<Subject>(
        MaterialPageRoute(builder: (_) => SubjectFormPage(initial: initial)),
      );

  @override
  State<SubjectFormPage> createState() => _SubjectFormPageState();
}

class _SubjectFormPageState extends State<SubjectFormPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  ApiException? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final name = _name.text.trim();
    final study = StudyScope.read(context);
    final initial = widget.initial;
    setState(() => _saving = true);
    final Subject? saved;
    try {
      saved = initial == null
          ? await study.createSubject(name)
          : await study.renameSubject(initial.id, name);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
      showError(context, error);
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
        initial == null ? 'Subject added' : 'Subject renamed',
        todayStale:
            initial != null && DashboardScope.read(context).loadError != null,
      ),
    );
    Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New subject' : 'Rename subject'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            TextFormField(
              controller: _name,
              autofocus: widget.initial == null,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Subject name',
                hintText: 'e.g. DBMS, Organic Chemistry',
                // A duplicate name is a 409 with no field details.
                errorText: error?.statusCode == 409
                    ? error!.message
                    : error?.fieldMessage('name'),
                errorMaxLines: 3,
              ),
              validator: (text) =>
                  (text ?? '').trim().isEmpty ? 'Enter a subject name' : null,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 24),
            SolidAction(label: _saving ? 'Saving…' : 'Save', onTap: _save),
          ],
        ),
      ),
    );
  }
}
