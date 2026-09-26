import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/widgets/select_field.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/study/data/api_study_repository.dart';
import 'package:omnia_ui/features/study/domain/exam.dart';
import 'package:omnia_ui/features/study/exam_detail_page.dart';
import 'package:omnia_ui/features/study/exam_form_page.dart';
import 'package:omnia_ui/features/study/study_page.dart';
import 'package:omnia_ui/features/study/subject_detail_page.dart';
import 'package:omnia_ui/features/study/subject_form_page.dart';
import 'package:omnia_ui/features/settings/settings_page.dart';

import 'support/fake_auth_backend.dart';
import 'support/select.dart';
import 'track_logging_test.dart'
    show backend, enter, field, reveal, sam, startApp, tapButton, tapCard;

/// Today's exam headline, as the Today card writes it.
Finder todayExam(String text) =>
    find.descendant(of: find.byType(HomePage), matching: find.text(text));

Future<void> openStudy(WidgetTester tester) => tapCard(tester, 'Study');

Future<void> saveForm(WidgetTester tester) =>
    tapButton(tester, find.widgetWithText(SolidAction, 'Save'));

Future<void> addSubject(WidgetTester tester, String name) async {
  await tapButton(tester, find.byTooltip('Add subject'));
  await enter(tester, 'Subject name', name);
  await saveForm(tester);
}

/// Accepts the date picker's preselected day: the server's today.
Future<void> pickToday(WidgetTester tester) async {
  await tapButton(tester, find.widgetWithText(PickerField, 'Date'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Leaves Study for Today's first screen.
Future<void> backToToday(WidgetTester tester) async {
  await tester.tap(find.text('Today').last);
  await tester.pumpAndSettle();
}

/// A fresh launch against the same server: the stored token signs in again.
Future<void> restart(WidgetTester tester, FakeAuthBackend server) async {
  await tester.pumpWidget(const SizedBox());
  await startApp(tester, server);
}

List<Map<String, dynamic>> bodies(FakeAuthBackend server, String request) => [
  for (final entry in server.studyWrites)
    if (entry.$1 == request) entry.$2,
];

void main() {
  group('API mode', () {
    testWidgets('no subjects or exams: empty states, never a sample', (
      tester,
    ) async {
      await startApp(tester, backend());
      expect(todayExam('No exams coming up.'), findsOneWidget);
      await openStudy(tester);
      expect(find.byType(StudyPage), findsOneWidget);
      expect(find.text('No exams yet.'), findsOneWidget);
      expect(find.text('No subjects yet.'), findsOneWidget);
      expect(find.textContaining('DBMS'), findsNothing);
      expect(find.text('SAMPLE'), findsNothing);
    });

    testWidgets('a new subject is stored and survives a restart', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openStudy(tester);
      await addSubject(tester, '  Organic Chemistry ');
      expect(find.byType(SubjectFormPage), findsNothing);
      expect(find.text('Subject added.'), findsOneWidget);
      expect(find.text('Organic Chemistry'), findsOneWidget);
      expect(server.subjectsOf(sam).single['name'], 'Organic Chemistry');

      await restart(tester, server);
      await openStudy(tester);
      expect(find.text('Organic Chemistry'), findsOneWidget);
    });

    testWidgets(
      'an exam is linked to a picked subject, shows on Today and persists',
      (tester) async {
        final server = backend();
        final biology = server.addSubject(sam, 'Biology');
        server.addSubject(sam, 'Physics');
        await startApp(tester, server);
        await openStudy(tester);
        await tapButton(tester, find.byTooltip('Add exam'));
        expect(find.byType(ExamFormPage), findsOneWidget);
        // Picked from the user's subjects; there is no subject text field.
        expect(field('Subject'), findsNothing);
        await pick(tester, 'Subject', 'Biology');
        await enter(tester, 'Exam', 'Unit test');
        await pickToday(tester);
        await saveForm(tester);

        expect(bodies(server, 'POST /study/exams').single, {
          'subject_id': biology,
          'title': 'Unit test',
          'exam_date': '2026-09-24',
          'notes': null,
        });
        expect(find.text('Exam added.'), findsOneWidget);
        expect(find.text('Unit test'), findsOneWidget);
        expect(find.text('TODAY'), findsWidgets);

        await backToToday(tester);
        expect(todayExam('Your Biology exam is today.'), findsOneWidget);

        await restart(tester, server);
        expect(todayExam('Your Biology exam is today.'), findsOneWidget);
        await openStudy(tester);
        expect(find.text('Unit test'), findsOneWidget);
      },
    );

    testWidgets('deleting the last exam clears Today', (tester) async {
      final server = backend()
        ..setNextExam(
          sam,
          subject: 'Biology',
          title: 'Unit test',
          date: '2026-10-02',
          daysLeft: 8,
        );
      await startApp(tester, server);
      expect(todayExam('Your Biology exam is in 8 days.'), findsOneWidget);
      await openStudy(tester);
      await tapButton(tester, find.text('Unit test'));
      expect(find.byType(ExamDetailPage), findsOneWidget);
      await tapButton(tester, find.text('Delete'));
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Exam deleted.'), findsOneWidget);
      expect(find.text('No exams yet.'), findsOneWidget);
      await backToToday(tester);
      expect(todayExam('No exams coming up.'), findsOneWidget);
      expect(find.textContaining('Biology exam'), findsNothing);
    });

    testWidgets('editing an exam updates Study and Today', (tester) async {
      final server = backend()
        ..setNextExam(
          sam,
          subject: 'Biology',
          title: 'Unit test',
          date: '2026-10-02',
          daysLeft: 8,
        );
      await startApp(tester, server);
      await openStudy(tester);
      await tapButton(tester, find.text('Unit test'));
      await tapButton(tester, find.widgetWithText(SolidAction, 'Edit'));
      expect(find.text('Biology'), findsOneWidget, reason: 'pre-filled');
      expect(find.text('Friday, October 2'), findsOneWidget);
      await enter(tester, 'Exam', 'Final');
      await saveForm(tester);
      expect(find.text('Final'), findsOneWidget, reason: 'detail, live');
      await backToToday(tester);
      expect(todayExam('Final  ·  Friday, October 2'), findsOneWidget);
    });

    testWidgets('renaming a subject renames it on its exams and Today', (
      tester,
    ) async {
      final server = backend()
        ..setNextExam(
          sam,
          subject: 'Bio',
          title: 'Unit test',
          date: '2026-10-02',
          daysLeft: 8,
        );
      await startApp(tester, server);
      await openStudy(tester);
      await tapButton(tester, find.text('Bio'));
      expect(find.byType(SubjectDetailPage), findsOneWidget);
      await tapButton(tester, find.text('Rename'));
      expect(find.text('Bio'), findsOneWidget, reason: 'pre-filled');
      await enter(tester, 'Subject name', 'Biology');
      await saveForm(tester);
      expect(find.text('Biology'), findsOneWidget);
      await backToToday(tester);
      expect(todayExam('Your Biology exam is in 8 days.'), findsOneWidget);
    });

    testWidgets('deleting a subject says its exams go too, and they do', (
      tester,
    ) async {
      final server = backend()
        ..setNextExam(
          sam,
          subject: 'Biology',
          title: 'Unit test',
          date: '2026-10-02',
          daysLeft: 8,
        );
      await startApp(tester, server);
      await openStudy(tester);
      await tapButton(tester, find.text('Biology'));
      await tapButton(tester, find.text('Delete'));
      expect(
        find.textContaining('its 1 upcoming exam will be removed'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('No subjects yet.'), findsOneWidget);
      expect(find.text('No exams yet.'), findsOneWidget);
      expect(server.examsOf(sam), isEmpty);
      await backToToday(tester);
      expect(todayExam('No exams coming up.'), findsOneWidget);
    });

    testWidgets('invalid input is explained; nothing is sent', (tester) async {
      final server = backend()..addSubject(sam, 'Biology');
      await startApp(tester, server);
      await openStudy(tester);
      await tapButton(tester, find.byTooltip('Add subject'));
      await saveForm(tester);
      expect(find.text('Enter a subject name'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tapButton(tester, find.byTooltip('Add exam'));
      await saveForm(tester);
      expect(find.text('Choose a subject'), findsOneWidget);
      expect(find.text('Enter the exam'), findsOneWidget);
      expect(find.text('Choose the exam date'), findsOneWidget);
      expect(server.studyWrites, isEmpty);
    });

    testWidgets('a duplicate subject name is refused under the field', (
      tester,
    ) async {
      final server = backend()..addSubject(sam, 'Biology');
      await startApp(tester, server);
      await openStudy(tester);
      await addSubject(tester, 'Biology');
      expect(find.byType(SubjectFormPage), findsOneWidget, reason: 'kept');
      expect(
        find.text('You already have a subject with this name'),
        findsWidgets,
      );
      expect(field('Subject name'), findsOneWidget);
      expect(find.text('Biology'), findsWidgets, reason: 'input kept');
      expect(server.subjectsOf(sam), hasLength(1));
    });

    testWidgets('with no subjects, Add exam leads to adding one first', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openStudy(tester);
      await tapButton(tester, find.widgetWithText(SolidAction, 'Add exam'));
      expect(find.text('Add a subject first.'), findsOneWidget);
      await tapButton(tester, find.widgetWithText(SolidAction, 'New subject'));
      await enter(tester, 'Subject name', 'Physics');
      await saveForm(tester);
      // Back on the exam form, with the new subject chosen.
      expect(find.byType(ExamFormPage), findsOneWidget);
      expect(find.widgetWithText(PickerField, 'Physics'), findsOneWidget);
      await enter(tester, 'Exam', 'Mock paper');
      await pickToday(tester);
      await saveForm(tester);
      expect(server.examsOf(sam).single['title'], 'Mock paper');
    });

    testWidgets('offline: the form keeps its input and says why', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openStudy(tester);
      await tapButton(tester, find.byTooltip('Add subject'));
      await enter(tester, 'Subject name', 'Physics');
      server.offline = true;
      await saveForm(tester);
      expect(find.byType(SubjectFormPage), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Physics'), findsOneWidget);
    });

    testWidgets('a failed first load offers a retry, not an empty state', (
      tester,
    ) async {
      final server = backend()..studyDown = true;
      await startApp(tester, server);
      await openStudy(tester);
      expect(find.text('No exams yet.'), findsNothing);
      expect(find.text("Couldn't load your study."), findsWidgets);
      server.studyDown = false;
      await tapButton(tester, find.text('Try again').first);
      expect(find.text('No exams yet.'), findsOneWidget);
    });
  });

  testWidgets('mock mode keeps its labelled sample and stays consistent', (
    tester,
  ) async {
    await startApp(tester, null);
    expect(todayExam('Your DBMS exam is in 8 days.'), findsOneWidget);
    await openStudy(tester);
    expect(find.text('SAMPLE'), findsWidgets);
    expect(find.text('DBMS exam'), findsOneWidget);
    await tapButton(tester, find.text('DBMS exam'));
    await tapButton(tester, find.text('Delete'));
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    await backToToday(tester);
    // Opening Study scrolled Today down to its card; scroll back up.
    await tester.scrollUntilVisible(
      todayExam('No exams coming up.'),
      -200,
      scrollable: find
          .descendant(
            of: find.byType(HomePage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(todayExam('No exams coming up.'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('Study and its forms fit 200% text on a 360px phone '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = backend()
        ..setNextExam(
          sam,
          subject: 'Organic Chemistry',
          title: 'End-of-semester practical examination',
          date: '2026-10-02',
          daysLeft: 8,
        );
      await startApp(tester, server, size: const Size(360, 800));
      if (dark) {
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await reveal(tester, SettingsPage, find.text('Dark'));
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
      Future<void> scrollThrough() async {
        for (var i = 0; i < 6; i++) {
          await tester.drag(
            find.byType(Scrollable).hitTestable().first,
            const Offset(0, -300),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }

      await openStudy(tester);
      await scrollThrough();
      final exam = find.text('End-of-semester practical examination');
      await tester.scrollUntilVisible(
        exam,
        -200,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
      await tapButton(tester, exam);
      expect(tester.takeException(), isNull);
      final edit = find.widgetWithText(SolidAction, 'Edit');
      await tester.scrollUntilVisible(
        edit,
        200,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
      await tapButton(tester, edit);
      await scrollThrough();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      final subject = find.text('Organic Chemistry').last;
      await tester.scrollUntilVisible(
        subject,
        200,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
      await tapButton(tester, subject);
      expect(find.byType(SubjectDetailPage), findsOneWidget);
      await scrollThrough();
    });
  }

  test('study JSON follows the backend contract', () {
    final exam = examFromApi(
      jsonDecode('''{
        "id": "e1", "title": "Midterm", "exam_date": "2026-10-02",
        "notes": null, "days_left": 8,
        "subject": {"id": "s1", "name": "Biology", "color": null}
      }''') as Map<String, dynamic>,
    );
    expect(
      (exam.id, exam.subjectId, exam.subjectName, exam.title),
      ('e1', 's1', 'Biology', 'Midterm'),
    );
    expect((exam.date, exam.daysLeft), (DateTime(2026, 10, 2), 8));
    expect(
      examToApi(
        ExamDraft(
          subjectId: 's1',
          title: 'Midterm',
          date: DateTime(2026, 10, 2),
        ),
      ),
      {
        'subject_id': 's1',
        'title': 'Midterm',
        'exam_date': '2026-10-02',
        'notes': null,
      },
      reason: 'null notes clear them on PATCH',
    );
    expect(subjectFromApi({'id': 's1', 'name': 'Biology'}).name, 'Biology');
  });
}
