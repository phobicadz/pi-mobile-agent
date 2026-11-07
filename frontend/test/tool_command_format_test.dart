import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/utils/code_highlight.dart';
import 'package:pi_mobile_agent/utils/dracula_scheme.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';

/// A command line of the shape this app actually shows: a directory change, a
/// build, a pipe, a redirect, and a quoted string at the end. A command with
/// none of those (`ls`) has nothing in it for a grammar to say anything about.
const _command =
    'cd /home/adam/source/repos/pi-mobile-agent && flutter build web 2>&1 | '
    'tail -20 && echo "built: ✓"';

Future<void> pumpBubble(WidgetTester tester, PiMessage message) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: Dracula.darkScheme(),
      brightness: Brightness.dark,
    ),
    home: Scaffold(
      body: ListView(children: [ChatBubble(message: message)]),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 120));
}

PiMessage withTool(PiTool tool) => PiMessage(
      id: 'm1',
      role: 'assistant',
      content: '',
      timestamp: DateTime(2026),
      toolCalls: [tool],
    );

void main() {
  testWidgets('a bash command is drawn as a shell command, not as prose',
      (tester) async {
    await pumpBubble(
        tester,
        withTool(PiTool(
          name: 'bash',
          arguments: {'command': _command},
          result: '✓ Built build/web',
        )));

    // The parameter name labels what follows, so the command is not a bare
    // block of text with no saying what it is.
    expect(find.text('command'), findsOneWidget);

    final block = tester.widget<HighlightedCode>(find.byWidgetPredicate(
        (w) => w is HighlightedCode && w.source == _command));
    expect(block.language, 'shell',
        reason: 'a command line is code, and the app already has a shell '
            'grammar - drawing it in the reply\'s proportional text is what '
            'made it read like part of the sentence');
    expect(block.textStyle?.fontFamily, 'JetBrainsMono');
    expect(block.isDark, isTrue,
        reason: 'the code theme follows the appearance the app is in');
  });

  testWidgets('the shell command is actually coloured, not just monospaced',
      (tester) async {
    final spans =
        highlightedSpans(_command, language: 'shell', isDark: true);

    // The colours are on the nested spans - a keyword or a quoted string is a
    // child of the block, not the block.
    final colours = <Color>{};
    void walk(InlineSpan span) {
      if (span is! TextSpan) return;
      final color = span.style?.color;
      if (color != null) colours.add(color);
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
    for (final span in spans) {
      walk(span);
    }

    expect(colours.length, greaterThan(1),
        reason: 'one colour is a monospace block, not syntax colouring. The '
            'grammar registered as `shell` is the session one - it colours what '
            'follows a \$ prompt and nothing else, which is why a command '
            'line with no prompt in it came out uncoloured');
  });

  testWidgets('a non-shell tool keeps its arguments as arguments',
      (tester) async {
    const path = '/home/adam/source/repos/pi-mobile-agent/README.md';
    await pumpBubble(
        tester,
        withTool(PiTool(
          name: 'read',
          arguments: {'path': path, 'offset': 12},
        )));

    // Monospace, because it is an argument and not a sentence - but not
    // coloured, because a path has no language to colour it with.
    final text = tester
        .widgetList<Text>(find.descendant(
            of: find.byType(ChatBubble), matching: find.text(path)))
        .first;
    expect(text.style?.fontFamily, 'JetBrainsMono');
    expect(find.byType(HighlightedCode), findsNothing,
        reason: 'guessing a language for a file path is a guess about a string '
            'that does not have one');
  });

  test('a shell tool is recognised by what its arguments are', () {
    // Pi names it `bash`; the others are the same thing said differently.
    for (final name in ['bash', 'shell', 'sh', 'run_command', 'terminal']) {
      expect(ChatBubble.isShellTool(name), isTrue, reason: name);
    }
    for (final name in ['read', 'edit', 'write', 'grep']) {
      expect(ChatBubble.isShellTool(name), isFalse, reason: name);
    }
  });
}
