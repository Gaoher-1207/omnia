import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_pressable.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/surface_shadow.dart';
import 'package:omnia_ui/features/areas/areas_page.dart';
import 'package:omnia_ui/features/assistant/assistant_page.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';
import 'package:omnia_ui/features/tasks/task_form_page.dart';

import 'track_logging_test.dart' show openAreasTab, reveal, startApp;

Widget host(
  Widget child, {
  bool dark = false,
  double scale = 1,
  bool reduceMotion = false,
}) => MaterialApp(
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(brightness: Brightness.dark),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduceMotion,
    ),
    child: app!,
  ),
  home: Scaffold(
    body: Center(
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  ),
);

/// Lets a press or release run to the end (it starts on the next frame).
Future<void> settled(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

/// Where [surface] is drawn now (it moves with the press).
Offset at(WidgetTester tester, Finder surface) => tester.getTopLeft(surface);

/// The hard shadow still showing beyond [surface]'s pressable.
Offset shadow(WidgetTester tester, Finder surface) => tester
    .widget<SurfaceShadow>(
      find.ancestor(of: surface, matching: find.byType(SurfaceShadow)).first,
    )
    .offset;

void main() {
  group('SolidAction presses into its shadow', () {
    late int taps;
    Finder button() => find.byType(FilledButton);

    Future<void> pump(WidgetTester tester, {bool dark = false}) {
      taps = 0;
      return tester.pumpWidget(
        host(
          SolidAction(label: 'Plan my day', onTap: () => taps++),
          dark: dark,
        ),
      );
    }

    testWidgets('rest, pointer down, pointer up', (tester) async {
      await pump(tester);
      final rest = at(tester, button());
      expect(shadow(tester, button()), const Offset(2, 2));

      final finger = await tester.startGesture(tester.getCenter(button()));
      await tester.pump(); // pointer down is handled at once…
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        at(tester, button()).dx,
        greaterThan(rest.dx),
        reason: 'moving within a frame, not after the tap is decided',
      );
      await settled(tester);
      expect(at(tester, button()), rest + const Offset(2, 2));
      expect(shadow(tester, button()), Offset.zero, reason: 'collapsed');
      expect(taps, 0, reason: 'nothing happens until release');

      await finger.up();
      await settled(tester);
      expect(at(tester, button()), rest);
      expect(shadow(tester, button()), const Offset(2, 2));
      expect(taps, 1);
    });

    testWidgets('a cancelled press returns without tapping', (tester) async {
      await pump(tester);
      final rest = at(tester, button());
      final finger = await tester.startGesture(tester.getCenter(button()));
      await settled(tester);
      expect(at(tester, button()), isNot(rest));
      await finger.cancel();
      await settled(tester);
      expect(at(tester, button()), rest);
      expect(shadow(tester, button()), const Offset(2, 2));
      expect(taps, 0);
    });

    testWidgets('dragging away (a scroll) lets go without tapping', (
      tester,
    ) async {
      await pump(tester);
      final rest = at(tester, button());
      final finger = await tester.startGesture(tester.getCenter(button()));
      await settled(tester);
      await finger.moveBy(const Offset(0, 40));
      await settled(tester);
      expect(at(tester, button()), rest);
      await finger.up();
      await settled(tester);
      expect(taps, 0);
    });

    testWidgets('each tap fires once, and a quick tap still shows the press', (
      tester,
    ) async {
      await pump(tester);
      final rest = at(tester, button());
      await tester.tap(button());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        at(tester, button()),
        isNot(rest),
        reason: 'visible even when brief',
      );
      await settled(tester);
      expect(at(tester, button()), rest);
      await tester.tap(button());
      await settled(tester);
      expect(taps, 2);
    });

    testWidgets('keyboard activation presses and fires once', (tester) async {
      await pump(tester);
      final rest = at(tester, button());
      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // focus the button
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(at(tester, button()), isNot(rest));
      await settled(tester);
      expect(at(tester, button()), rest);
      expect(taps, 1);
    });

    testWidgets('keeps its button semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expect(
        tester.getSemantics(button()),
        isSemantics(
          label: 'Plan my day',
          isButton: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('dark mode presses the same way', (tester) async {
      await pump(tester, dark: true);
      final rest = at(tester, button());
      final finger = await tester.startGesture(tester.getCenter(button()));
      await settled(tester);
      expect(at(tester, button()), rest + const Offset(2, 2));
      await finger.up();
      await settled(tester);
      expect(at(tester, button()), rest);
      expect(tester.takeException(), isNull);
    });
  });

  group('HardCard', () {
    testWidgets('with onTap it presses by its own shadow offset', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          HardCard(
            color: blue,
            shadowOffset: const Offset(2, 3),
            onTap: () => taps++,
            child: const Text('Ask Omnia'),
          ),
        ),
      );
      final text = find.text('Ask Omnia');
      final rest = at(tester, text);
      final finger = await tester.startGesture(tester.getCenter(text));
      await settled(tester);
      expect(at(tester, text), rest + const Offset(2, 3));
      expect(shadow(tester, text), Offset.zero);
      await finger.up();
      await settled(tester);
      expect(at(tester, text), rest);
      expect(shadow(tester, text), const Offset(2, 3));
      expect(taps, 1);
    });

    testWidgets('without onTap it is information and never moves', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const HardCard(color: paper, child: Text('Just facts'))),
      );
      expect(find.byType(OmniaPressable), findsNothing);
      final text = find.text('Just facts');
      final rest = at(tester, text);
      final finger = await tester.startGesture(tester.getCenter(text));
      await settled(tester);
      expect(at(tester, text), rest);
      expect(shadow(tester, text), const Offset(3, 4));
      await finger.up();
    });
  });

  group('OmniaPressable', () {
    testWidgets('disabled: stays put and its control does nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          OmniaPressable(
            radius: 9,
            enabled: false,
            builder: (context, states) => FilledButton(
              onPressed: null,
              statesController: states,
              child: const Text('Save'),
            ),
          ),
        ),
      );
      final button = find.byType(FilledButton);
      final rest = at(tester, button);
      final finger = await tester.startGesture(tester.getCenter(button));
      await settled(tester);
      expect(at(tester, button), rest);
      expect(shadow(tester, button), const Offset(3, 4));
      await finger.up();
      await settled(tester);
      expect(at(tester, button), rest);
    });

    testWidgets('reduced motion: pressed at once, released at once', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(SolidAction(label: 'Go', onTap: () {}), reduceMotion: true),
      );
      final button = find.byType(FilledButton);
      final rest = at(tester, button);
      final finger = await tester.startGesture(tester.getCenter(button));
      await tester.pump();
      expect(at(tester, button), rest + const Offset(2, 2), reason: 'no tween');
      await finger.up();
      await tester.pump();
      expect(at(tester, button), rest);
    });

    testWidgets('200% text on a narrow screen: no overflow, still presses', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HardCard(
                color: blue,
                onTap: () {},
                child: const Text('A long card label that has to wrap'),
              ),
              const SizedBox(height: 12),
              SolidAction(label: 'A long action label', onTap: () {}),
            ],
          ),
          dark: true,
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      final button = find.byType(FilledButton);
      final rest = at(tester, button);
      final finger = await tester.startGesture(tester.getCenter(button));
      await settled(tester);
      expect(at(tester, button), rest + const Offset(2, 2));
      await finger.up();
      await settled(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a save that is already running is not started twice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400); // the whole form fits
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saving = Completer<bool>();
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: TaskFormPage(
          onSave: (Task task) {
            saves++;
            return saving.future;
          },
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Lab');
    final save = find.byType(SolidAction);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('Saving…'), findsOneWidget, reason: 'loading state');
    await tester.tap(save);
    await settled(tester);
    expect(saves, 1);
    saving.complete(false);
    await settled(tester);
    expect(find.text('Add task'), findsOneWidget, reason: 'ready again');
  });

  group('in the app', () {
    Future<void> expectPresses(WidgetTester tester, Finder target) async {
      final rest = at(tester, target);
      final finger = await tester.startGesture(tester.getCenter(target));
      await settled(tester);
      expect(at(tester, target), isNot(rest), reason: 'pressed into shadow');
      await finger.cancel();
      await settled(tester);
      expect(at(tester, target), rest, reason: 'back up');
    }

    testWidgets('Today: Ask Omnia and the area cards are tactile', (
      tester,
    ) async {
      await startApp(tester, null);
      final ask = find.text('Ask Omnia');
      await reveal(tester, HomePage, ask);
      await expectPresses(tester, ask);
      final study = find.descendant(
        of: find.byType(HomePage),
        matching: find.text('Study'),
      );
      await reveal(tester, HomePage, study);
      await expectPresses(tester, study);
    });

    testWidgets('Areas tiles are tactile', (tester) async {
      await startApp(tester, null);
      await openAreasTab(tester);
      await expectPresses(
        tester,
        find.descendant(
          of: find.byType(AreasPage),
          matching: find.text('Tasks'),
        ),
      );
    });

    testWidgets('Assistant: suggestions press, chat bubbles never move', (
      tester,
    ) async {
      await startApp(tester, null);
      final ask = find.text('Ask Omnia');
      await reveal(tester, HomePage, ask);
      await tester.tap(ask);
      await tester.pumpAndSettle();
      final question = find.text('How am I doing today?');
      await expectPresses(tester, question);

      await tester.tap(question);
      await tester.pumpAndSettle();
      final bubble = find.descendant(
        of: find.byType(AssistantPage),
        matching: find.text('How am I doing today?'),
      );
      expect(
        find.ancestor(of: bubble, matching: find.byType(OmniaPressable)),
        findsNothing,
      );
      final rest = at(tester, bubble);
      final finger = await tester.startGesture(tester.getCenter(bubble));
      await settled(tester);
      expect(at(tester, bubble), rest);
      await finger.up();
    });
  });
}
