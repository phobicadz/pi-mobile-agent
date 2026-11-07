import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/utils/chat_palette.dart';
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

    // The card it sits in is painted from the scheme, so the block inside it has
    // to be too - a fixed one-dark grey in a Dracula card is two palettes in
    // the same box.
    expect(block.background, Dracula.background,
        reason: 'the command sits on Dracula\'s own background, inset from the '
            'card it is painted into');
    expect(block.background, isNot(codePalette(true).background),
        reason: 'not the code theme\'s background, which is the same colour in '
            'every scheme the app offers');
    expect(block.textStyle?.color, Dracula.foreground,
        reason: 'the parts of a command the grammar leaves alone - a path, a '
            'subcommand - are text, and they are the theme\'s text colour');
  });

  testWidgets('the command block is inset from the card it sits in, in either '
      'appearance', (tester) async {
    // Same claim at the other brightness: the surface scale runs the other way
    // in dark, so "one step in" is a different token per theme.
    for (final dark in [true, false]) {
      final scheme = dark
          ? Dracula.darkScheme()
          : ColorScheme.fromSeed(
              seedColor: Dracula.purple, brightness: Brightness.light);
      final palette = ChatPalette.from(
          ThemeData(useMaterial3: true, colorScheme: scheme));

      final step = palette.codeBackground.computeLuminance() -
          palette.toolCard.computeLuminance();
      expect(step.abs(), greaterThan(0.004),
        reason: 'a block the same colour as the card around it is not a block, '
            'it is the card (${dark ? 'dark' : 'light'})');
      // In dark it goes down from the card (toward the page), in light it goes
      // up toward the page. Either way the card reads as raised off the page.
      expect(step.isNegative, dark,
          reason: 'inset means toward the page at both brightnesses');
    }
  });

  testWidgets('every block of code in a reply is painted from the scheme',
      (tester) async {
    // A fenced block and a tool's output: the two other places a reply gets a
    // block of code, besides the command. One of them on the theme's surfaces
    // and the others on a fixed grey is a reply in two palettes.
    await pumpBubble(
        tester,
        PiMessage(
          id: 'm2',
          role: 'assistant',
          content: 'Here is the check:\n\n'
              '```typescript\nconst ok = health.status === "ok";\n```\n',
          timestamp: DateTime(2026),
          toolCalls: [PiTool(name: 'bash', arguments: {'command': 'ls'},
              result: '{"status":"ok","pi_connected":true}')],
        ));

    final blocks =
        tester.widgetList<HighlightedCode>(find.byType(HighlightedCode)).toList();
    expect(blocks.length, greaterThanOrEqualTo(2),
        reason: 'one fenced block and one tool result');
    for (final block in blocks) {
      expect(block.background, Dracula.background,
          reason: 'the block is inside a bubble the scheme already painted '
              '(${block.source.trim()})');
      expect(block.textStyle?.color, Dracula.foreground,
          reason: 'and its un-tokened text is the theme\'s text colour');
    }
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
