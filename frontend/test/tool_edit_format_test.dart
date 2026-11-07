import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/utils/chat_palette.dart';
import 'package:pi_mobile_agent/utils/code_highlight.dart';
import 'package:pi_mobile_agent/utils/dracula_scheme.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';

/// What an `edit` looks like coming from Pi: a path, and a list of pairs.
const _dartPath = 'frontend/lib/widgets/chat_bubble.dart';
const _old = 'final shell = isShellTool(tool.name);';
const _new =
    'final shell = isShellTool(tool.name);\n    final language = _languageOfTool(tool);';

PiMessage editMessage(Map<String, Object?> arguments) => PiMessage(
      id: 'e1',
      role: 'assistant',
      content: '',
      timestamp: DateTime(2026),
      toolCalls: [PiTool(name: 'edit', arguments: arguments)],
    );

Future<void> pump(WidgetTester tester, PiMessage message,
    {bool dark = true}) async {
  final scheme = dark
      ? Dracula.darkScheme()
      : ColorScheme.fromSeed(seedColor: Dracula.purple, brightness: Brightness.light);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: dark ? Brightness.dark : Brightness.light,
    ),
    home: Scaffold(body: ListView(children: [ChatBubble(message: message)])),
  ));
  await tester.pump(const Duration(milliseconds: 120));
}

List<HighlightedCode> blocks(WidgetTester tester) =>
    tester.widgetList<HighlightedCode>(find.byType(HighlightedCode)).toList();

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  testWidgets('an edit is drawn as the change it made, in the language of the '
      'file it changed', (tester) async {
    await pump(tester,
        editMessage({'path': _dartPath, 'edits': [
          {'oldText': _old, 'newText': _new},
        ]}));

    expect(find.text('- oldText'), findsOneWidget);
    expect(find.text('+ newText'), findsOneWidget);

    final found = blocks(tester);
    expect(found.length, 2,
        reason: 'one block per half. The pairs used to be printed as one value '
            '- [{oldText: <one line>, newText: <two lines>}] - which is the '
            'shape of an edit, not the edit');
    for (final block in found) {
      expect(block.language, 'dart',
          reason: 'the file being edited is what says the text is Dart - '
              'guessing from the text is how a shell command gets coloured by '
              'a Dart grammar');
    }
    expect(found.map((b) => b.source), containsAll([_old, _new]));
  });

  testWidgets('the two halves are told apart by colour, not only by the label',
      (tester) async {
    await pump(tester,
        editMessage({'path': _dartPath, 'edits': [
          {'oldText': _old, 'newText': _new},
        ]}));

    final palette =
        ChatPalette.from(ThemeData(useMaterial3: true, colorScheme: Dracula.darkScheme()));
    final found = blocks(tester);
    final removed = found.firstWhere((b) => b.source == _old);
    final added = found.firstWhere((b) => b.source == _new);

    expect(added.background, palette.addedBlock);
    expect(removed.background, palette.removedBlock);
    expect(added.background, isNot(removed.background),
        reason: 'a reader scrolling past two identical blocks cannot tell which '
            'is which, and the label is above the text, not beside it');
    expect(added.background, isNot(palette.codeBackground));
    expect(removed.background, isNot(palette.codeBackground));

    final labelAdded = tester.widget<Text>(find.text('+ newText'));
    final labelRemoved = tester.widget<Text>(find.text('- oldText'));
    expect(labelAdded.style?.color, palette.diffAdded);
    expect(labelRemoved.style?.color, palette.diffRemoved);
  });

  testWidgets('the tint stays a hint: the code on it is still legible, in '
      'either appearance', (tester) async {
    for (final dark in [true, false]) {
      final scheme = dark
          ? Dracula.darkScheme()
          : ColorScheme.fromSeed(
              seedColor: Dracula.purple, brightness: Brightness.light);
      final palette =
          ChatPalette.from(ThemeData(useMaterial3: true, colorScheme: scheme));
      final label = dark ? 'dark' : 'light';

      for (final entry in {
        'added': palette.addedBlock,
        'removed': palette.removedBlock,
      }.entries) {
        expect(
            contrast(palette.codeForeground, entry.value),
            greaterThan(4.5),
            reason: 'a tint strong enough to be a colour swatch is a tint the '
                'code theme\'s token colours stop working on ($label ${entry.key})');
        expect((entry.value.computeLuminance() - palette.codeBackground.computeLuminance()).abs(),
            greaterThan(0.002),
            reason: 'a tint nobody can see is a label and nothing else '
                '($label ${entry.key})');
      }
    }
  });

  testWidgets('the halves stay in the order a diff is read in, for every pair',
      (tester) async {
    await pump(tester,
        editMessage({'path': _dartPath, 'edits': [
          {'oldText': 'one', 'newText': 'two'},
          {'oldText': 'three', 'newText': 'four'},
        ]}));

    final found = blocks(tester);
    expect(found.length, 4);
    final order = found
      ..sort((a, b) => tester
          .getRect(find.byWidget(a))
          .top
          .compareTo(tester.getRect(find.byWidget(b)).top));
    expect(order.map((b) => b.source), ['one', 'two', 'three', 'four'],
        reason: 'removed then added, pair after pair - the order the change '
            'happened in');
  });

  testWidgets('a file written whole is one added block', (tester) async {
    await pump(tester,
        editMessage({'path': 'backend/src/notification-prefs.ts',
            'content': 'export const key = "pi-mobile";\n'}));

    expect(find.text('+ content'), findsOneWidget);
    final block = blocks(tester).single;
    expect(block.language, 'typescript');
  });

  testWidgets('an edit to a document is not coloured by a guess', (tester) async {
    await pump(tester, editMessage({
      'path': 'AGENTS.md',
      'edits': [
        {'oldText': 'old paragraph', 'newText': 'new paragraph'}
      ],
    }));

    for (final block in blocks(tester)) {
      expect(block.language, 'plaintext',
          reason: 'the file viewer\'s own rule, applied here: a document is not '
              'something to colour, and auto-detection over the registered '
              'grammars would colour it anyway');
    }
  });

  testWidgets('an edit that spells its halves as plain arguments is still a '
      'diff', (tester) async {
    // The other spelling the same tool uses, with no `edits` list in sight.
    await pump(tester, editMessage({'path': _dartPath, 'oldText': _old, 'newText': _new}));

    expect(find.text('- oldText'), findsOneWidget);
    expect(find.text('+ newText'), findsOneWidget);
    expect(blocks(tester).map((b) => b.source), containsAll([_old, _new]));
  });
}
