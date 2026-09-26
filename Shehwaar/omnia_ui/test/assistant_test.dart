import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/assistant/assistant_controller.dart';
import 'package:omnia_ui/features/assistant/assistant_page.dart';
import 'package:omnia_ui/features/assistant/data/mock_assistant_repository.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_message.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_repository.dart';
import 'package:omnia_ui/features/home/home_page.dart';

import 'track_logging_test.dart' show reveal, startApp;

/// Answers only when the test says so, and records what it was asked.
class ScriptedAssistant implements AssistantRepository {
  final asked = <(String, List<AssistantMessage>)>[];
  final _replies = <Completer<String>>[];

  @override
  Future<String> ask(String message, List<AssistantMessage> history) {
    asked.add((message, List.of(history)));
    final reply = Completer<String>();
    _replies.add(reply);
    return reply.future;
  }

  void answer(String text) => _replies.last.complete(text);
  void fail(Object error) => _replies.last.completeError(error);
}

const offline = ApiException(
  statusCode: 503,
  code: 'service_unavailable',
  message: "Omnia's assistant is offline right now. Try again in a moment.",
);
const failed = ApiException(
  statusCode: 502,
  code: 'upstream_error',
  message: 'Omnia took too long to answer. Try again.',
);

/// The page on its own, with the session's scopes above it.
Widget host(
  AssistantController controller, {
  bool dark = false,
  double scale = 1,
}) => AppDependenciesScope(
  dependencies: AppDependencies.mock(),
  child: AssistantScope(
    controller: controller,
    child: MaterialApp(
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const AssistantPage(),
    ),
  ),
);

Finder get composer => find.byType(TextField);

Future<void> openAssistant(WidgetTester tester) async {
  final entry = find.text('Ask Omnia');
  await reveal(tester, HomePage, entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(composer, text);
  await tester.pump();
  await tester.tap(find.byTooltip('Send'));
  await tester.pump();
}

void main() {
  group('controller', () {
    test(
      'asks, shows the question while waiting, then keeps both turns',
      () async {
        final repo = ScriptedAssistant();
        final controller = AssistantController(repo);
        addTearDown(controller.dispose);
        var notified = 0;
        controller.addListener(() => notified++);

        final sent = controller.send('  What is due?  ');
        expect(controller.sending, isTrue);
        expect(controller.pending, 'What is due?');
        expect(controller.isEmpty, isFalse);
        expect(repo.asked.single.$1, 'What is due?');

        repo.answer('The assignment.');
        await sent;
        expect(controller.sending, isFalse);
        expect(controller.pending, isNull);
        expect(controller.error, isNull);
        expect(
          [for (final m in controller.messages) (m.role, m.text)],
          [
            (AssistantRole.user, 'What is due?'),
            (AssistantRole.assistant, 'The assignment.'),
          ],
        );
        expect(notified, greaterThanOrEqualTo(2));
      },
    );

    test('sends the earlier turns as history', () async {
      final repo = ScriptedAssistant();
      final controller = AssistantController(repo);
      addTearDown(controller.dispose);
      final first = controller.send('One');
      repo.answer('Uno');
      await first;
      final second = controller.send('Two');
      repo.answer('Dos');
      await second;
      expect(repo.asked.last.$1, 'Two');
      expect([for (final m in repo.asked.last.$2) m.text], ['One', 'Uno']);
      expect(controller.messages, hasLength(4));
    });

    test(
      'ignores blank questions and a second send while one is in flight',
      () async {
        final repo = ScriptedAssistant();
        final controller = AssistantController(repo);
        addTearDown(controller.dispose);
        await controller.send('   ');
        expect(repo.asked, isEmpty);

        final first = controller.send('First');
        await controller.send('Second');
        await controller.retry();
        expect(repo.asked, hasLength(1));
        repo.answer('ok');
        await first;
        expect(controller.messages.first.text, 'First');
      },
    );

    test('names each kind of failure', () async {
      for (final (error, kind) in [
        (offline, AssistantFailure.unavailable),
        (ApiException.network(), AssistantFailure.network),
        (failed, AssistantFailure.other),
        (StateError('boom'), AssistantFailure.other),
      ]) {
        final repo = ScriptedAssistant();
        final controller = AssistantController(repo);
        final sent = controller.send('Hi');
        repo.fail(error);
        await sent;
        expect(controller.failure, kind, reason: '$error');
        expect(controller.pending, 'Hi', reason: 'kept for Retry');
        expect(controller.messages, isEmpty);
        controller.dispose();
      }
    });

    test(
      'retry asks the failed question again with the same history',
      () async {
        final repo = ScriptedAssistant();
        final controller = AssistantController(repo);
        addTearDown(controller.dispose);
        final first = controller.send('Hi');
        repo.fail(offline);
        await first;

        final again = controller.retry();
        expect(controller.error, isNull, reason: 'cleared while retrying');
        expect(controller.sending, isTrue);
        repo.answer('Hello');
        await again;
        expect(repo.asked.map((a) => a.$1), ['Hi', 'Hi']);
        expect(controller.failure, isNull);
        expect(controller.messages.last.text, 'Hello');
      },
    );

    test('a new question replaces a failed one', () async {
      final repo = ScriptedAssistant();
      final controller = AssistantController(repo);
      addTearDown(controller.dispose);
      final first = controller.send('Old');
      repo.fail(failed);
      await first;
      final next = controller.send('New');
      repo.answer('Answer');
      await next;
      expect([for (final m in controller.messages) m.text], ['New', 'Answer']);
    });

    test('an answer arriving after dispose is dropped quietly', () async {
      final repo = ScriptedAssistant();
      final controller = AssistantController(repo);
      final sent = controller.send('Hi');
      controller.dispose();
      repo.answer('late');
      await expectLater(sent, completes);

      final failingRepo = ScriptedAssistant();
      final failing = AssistantController(failingRepo);
      final lost = failing.send('Hi');
      failing.dispose();
      failingRepo.fail(offline);
      await expectLater(lost, completes);
    });
  });

  group('mock repository', () {
    test('gives a sample answer to every suggestion', () async {
      final repo = MockAssistantRepository(delay: Duration.zero);
      final answers = {
        for (final question in AssistantPage.suggestions)
          await repo.ask(question, const []),
      };
      expect(answers, hasLength(AssistantPage.suggestions.length));
      expect(answers.every((a) => a.isNotEmpty), isTrue);
      expect(
        await repo.ask('What exams do I have?', const []),
        contains('DBMS exam'),
      );
      expect(await repo.ask('anything else', const []), isNotEmpty);
    });
  });

  group('mock mode', () {
    testWidgets('Today opens Ask Omnia; a suggestion is answered as a sample', (
      tester,
    ) async {
      await startApp(tester, null);
      await openAssistant(tester);
      expect(find.byType(AssistantPage), findsOneWidget);
      expect(find.text('SAMPLE'), findsOneWidget);
      expect(find.textContaining('sample answers'), findsOneWidget);
      for (final question in AssistantPage.suggestions) {
        expect(find.text(question), findsOneWidget);
      }

      await tester.tap(find.text('What exams do I have coming up?'));
      await tester.pump();
      expect(find.text('Omnia is thinking…'), findsOneWidget);
      expect(tester.widget<TextField>(composer).enabled, isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
            )
            .onPressed,
        isNull,
      );

      await tester.pumpAndSettle();
      expect(find.text('Omnia is thinking…'), findsNothing);
      expect(find.text('What exams do I have coming up?'), findsOneWidget);
      expect(find.textContaining('DBMS exam in 8 days'), findsOneWidget);
      expect(tester.widget<TextField>(composer).enabled, isTrue);
    });

    testWidgets(
      'typed questions are sent; the conversation stays for the session',
      (tester) async {
        await startApp(tester, null);
        await openAssistant(tester);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
              )
              .onPressed,
          isNull,
          reason: 'nothing to send yet',
        );
        await type(tester, 'How am I doing today?');
        expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
        await tester.pumpAndSettle();
        expect(find.textContaining('135 of 240 study minutes'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(AssistantPage), findsNothing);
        await openAssistant(tester);
        expect(
          find.text('How am I doing today?'),
          findsOneWidget,
          reason: 'kept',
        );
      },
    );
  });

  group('page states', () {
    testWidgets(
      'unavailable, network and other failures each offer Try again',
      (tester) async {
        for (final (error, title) in [
          (offline, "Omnia's assistant is unavailable"),
          (ApiException.network(), 'No answer from OMNIA'),
          (failed, "Omnia couldn't answer"),
        ]) {
          final repo = ScriptedAssistant();
          final controller = AssistantController(repo);
          await tester.pumpWidget(host(controller));
          await type(tester, 'Hi');
          repo.fail(error);
          await tester.pumpAndSettle();
          expect(find.text(title), findsOneWidget);
          expect(find.text(error.message), findsOneWidget);
          expect(find.text('Hi'), findsOneWidget, reason: 'the question stays');

          await tester.tap(find.text('Try again'));
          await tester.pump();
          expect(find.text(title), findsNothing);
          expect(find.text('Omnia is thinking…'), findsOneWidget);
          repo.answer('Hello there');
          await tester.pumpAndSettle();
          expect(find.text('Hello there'), findsOneWidget);
          expect(repo.asked, hasLength(2));
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      },
    );

    testWidgets('dark mode and 200% text: no overflow, readable bubbles', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = ScriptedAssistant();
      final controller = AssistantController(repo);
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(controller, dark: true, scale: 2));
      expect(tester.takeException(), isNull, reason: 'intro');

      await type(tester, 'What should I prioritize tonight?');
      repo.answer('Finish the assignment, then revise DBMS for 45 minutes.');
      await tester.pumpAndSettle();
      await type(tester, 'And after that?');
      repo.fail(offline);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'conversation');
      expect(find.text('Try again'), findsOneWidget);

      Color? colorOf(String text) => tester
          .firstWidget<RichText>(
            find.descendant(
              of: find.text(text),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.color;
      // Big text pushes the question above the failure card; scroll to it.
      await tester.scrollUntilVisible(
        find.text('And after that?'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(AssistantPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull, reason: 'scrolled');
      // The user's bubble is light blue in dark mode, so its text is ink.
      expect(colorOf('And after that?'), ink);
    });

    testWidgets(
      'screen readers get speakers, a live thinking state and buttons',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final repo = ScriptedAssistant();
        final controller = AssistantController(repo);
        addTearDown(controller.dispose);
        await tester.pumpWidget(host(controller));

        // HardCard reads as one node, as on Today: the heading, then its text.
        final intro = tester.getSemantics(find.text('Ask about your day'));
        expect(intro, isSemantics(isHeader: true));
        expect(intro.label, startsWith('Ask about your day\n'));
        expect(
          tester.getSemantics(find.text('How am I doing today?')),
          isSemantics(isButton: true, hasTapAction: true),
        );
        expect(
          tester.getSemantics(find.byTooltip('Send')),
          isSemantics(tooltip: 'Send', isButton: true),
        );

        await type(tester, 'Hi');
        expect(
          tester.getSemantics(find.text('Omnia is thinking…')),
          isSemantics(isLiveRegion: true),
        );
        repo.answer('Hello');
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp(r'^YOU\nHi$')), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp(r'^OMNIA\nHello$')),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(find.text('Hello')),
          isSemantics(isLiveRegion: true),
        );
        semantics.dispose();
      },
    );
  });

  test('only ApiClient speaks HTTP, and only data classes use ApiClient', () {
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      final source = file.readAsStringSync();
      if (path != 'lib/core/api/api_client.dart') {
        expect(source, isNot(contains('package:http/')), reason: path);
        expect(source, isNot(contains('dart:io')), reason: path);
      }
      final allowed =
          path == 'lib/app.dart' ||
          path.startsWith('lib/core/') ||
          RegExp(r'^lib/features/[^/]+/data/').hasMatch(path);
      if (!allowed) {
        expect(source, isNot(contains('api/api_client.dart')), reason: path);
      }
    }
  });
}
