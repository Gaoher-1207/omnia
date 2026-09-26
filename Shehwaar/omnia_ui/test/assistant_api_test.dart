import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/auth/token_store.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/features/assistant/assistant_page.dart';
import 'package:omnia_ui/features/assistant/data/api_assistant_repository.dart';
import 'package:omnia_ui/features/assistant/data/mock_assistant_repository.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_message.dart';

import 'assistant_test.dart' show composer, openAssistant, type;
import 'track_logging_test.dart'
    show ada, backend, clientFor, failure, field, openSettings, sam, startApp;

void main() {
  group('ApiAssistantRepository', () {
    test(
      'sends only the question and recent turns, as the signed-in user',
      () async {
        final server = backend();
        final repo = ApiAssistantRepository(await clientFor(server));
        final history = [
          for (var i = 0; i < 12; i++)
            i.isEven
                ? AssistantMessage.user('q$i')
                : AssistantMessage.assistant(i == 11 ? 'x' * 2500 : 'a$i'),
        ];

        expect(
          await repo.ask('What is due?', history),
          'Answer to: What is due?',
        );
        final (email, body) = server.chats.single;
        expect(email, sam);
        expect(body.keys, unorderedEquals(['message', 'history']));
        expect(body['message'], 'What is due?');
        final sent = body['history'] as List;
        expect(sent, hasLength(ApiAssistantRepository.maxHistory));
        expect(sent.first, {
          'role': 'user',
          'content': 'q2',
        }, reason: 'the latest 10');
        expect((sent.last as Map)['role'], 'assistant');
        expect(
          ((sent.last as Map)['content'] as String).length,
          ApiAssistantRepository.maxTurnLength,
        );
      },
    );

    test(
      'offline assistant is a 503; no connection is a network error',
      () async {
        final server = backend()..assistantDown = true;
        final repo = ApiAssistantRepository(await clientFor(server));
        final down = await failure(repo.ask('Hi', const []));
        expect(down.isUnavailable, isTrue);
        expect(down.message, contains('offline'));

        server.offline = true;
        expect((await failure(repo.ask('Hi', const []))).isNetwork, isTrue);
      },
    );

    testWidgets('waits for a slow first answer past the usual 20 s timeout', (
      tester,
    ) async {
      final api = ApiClient(
        baseUrl: 'http://omnia.test/api',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          await Future<void>.delayed(const Duration(seconds: 50));
          return http.Response(
            jsonEncode({'reply': 'Loaded.', 'source': 'ollama'}),
            200,
          );
        }),
      );
      addTearDown(api.close);
      String? reply;
      unawaited(
        ApiAssistantRepository(api).ask('Hi', const []).then((r) => reply = r),
      );
      await tester.pump(const Duration(seconds: 30));
      expect(reply, isNull);
      await tester.pump(const Duration(seconds: 21));
      expect(reply, 'Loaded.');
    });

    test('mock and API modes get their own repositories', () async {
      expect(AppDependencies.mock().assistant, isA<MockAssistantRepository>());
      expect(
        AppDependencies.api(await clientFor(backend())).assistant,
        isA<ApiAssistantRepository>(),
      );
    });
  });

  group('API mode', () {
    testWidgets('answers come from the backend, never a sample', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openAssistant(tester);
      expect(find.text('SAMPLE'), findsNothing);
      expect(find.textContaining("can't change anything"), findsOneWidget);

      await tester.tap(find.text('What tasks are most urgent?'));
      await tester.pumpAndSettle();
      expect(
        find.text('Answer to: What tasks are most urgent?'),
        findsOneWidget,
      );
      expect(server.chats.single.$2['history'], isEmpty);

      await type(tester, 'And tomorrow?');
      await tester.pumpAndSettle();
      expect(find.text('Answer to: And tomorrow?'), findsOneWidget);
      expect(server.chats.last.$2['history'], [
        {'role': 'user', 'content': 'What tasks are most urgent?'},
        {
          'role': 'assistant',
          'content': 'Answer to: What tasks are most urgent?',
        },
      ]);
    });

    testWidgets('an offline assistant says so and recovers on Try again', (
      tester,
    ) async {
      final server = backend()..assistantDown = true;
      await startApp(tester, server);
      await openAssistant(tester);
      await type(tester, 'Hi');
      await tester.pumpAndSettle();
      expect(find.text("Omnia's assistant is unavailable"), findsOneWidget);
      expect(find.textContaining('offline right now'), findsOneWidget);

      server.assistantDown = false;
      await tester.tap(find.widgetWithText(SolidAction, 'Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Answer to: Hi'), findsOneWidget);
      expect(find.text("Omnia's assistant is unavailable"), findsNothing);
    });

    testWidgets('no connection is reported as a network problem', (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openAssistant(tester);
      server.offline = true;
      await type(tester, 'Hi');
      await tester.pumpAndSettle();
      expect(find.text('No answer from OMNIA'), findsOneWidget);
      expect(find.textContaining("Can't reach OMNIA"), findsOneWidget);
      expect(tester.widget<TextField>(composer).enabled, isTrue);
    });

    testWidgets("the next user never sees the last user's conversation", (
      tester,
    ) async {
      final server = backend();
      await startApp(tester, server);
      await openAssistant(tester);
      await type(tester, 'Sam question');
      await tester.pumpAndSettle();
      expect(find.text('Sam question'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await openSettings(tester);
      final signOut = find.widgetWithText(ListTile, 'Sign out');
      await tester.ensureVisible(signOut);
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Email'), ada);
      await tester.enterText(field('Password'), 'ada-password');
      await tester.tap(find.widgetWithText(SolidAction, 'Sign in'));
      await tester.pumpAndSettle();

      await openAssistant(tester);
      expect(find.text('Sam question'), findsNothing);
      expect(find.text('Answer to: Sam question'), findsNothing);
      expect(find.text('Try asking'), findsOneWidget, reason: 'a fresh start');
      expect(find.byType(AssistantPage), findsOneWidget);
    });
  });
}
