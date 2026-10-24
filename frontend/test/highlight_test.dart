import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pi_mobile_agent/utils/code_highlight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';

void main() {
  testWidgets('fenced code block renders with syntax highlighting',
      (WidgetTester tester) async {
    const markdown = '''
Here is some code:

```python
def hello():
    print("world")
```
''';

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: ListView(
          children: [
            ChatBubble(
              message: PiMessage(
                id: '1',
                role: 'assistant',
                content: markdown,
                timestamp: DateTime.now(),
              ),
            ),
          ],
        ),
      ),
    ));

    // The HighlightedCode widget should be present in the tree.
    expect(find.byType(HighlightedCode), findsOneWidget);

    // The highlighted code should be rendered as RichText spans, not plain text.
    final richTexts = find.byType(RichText);
    expect(richTexts, findsWidgets);
  });

  testWidgets('code fence without a language tag still renders safely',
      (WidgetTester tester) async {
    // Bare fences carry no language info string; the highlighter auto-detects
    // instead of crashing the bubble.
    const markdown = '''
```
def hello():
    print("world")
```
''';

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: ListView(
          children: [
            ChatBubble(
              message: PiMessage(
                id: '1',
                role: 'assistant',
                content: markdown,
                timestamp: DateTime.now(),
              ),
            ),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.byType(HighlightedCode), findsOneWidget);
  });

  testWidgets('plain text without fences does not highlight code',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: ListView(
          children: [
            ChatBubble(
              message: PiMessage(
                id: '1',
                role: 'assistant',
                content: 'no code here',
                timestamp: DateTime.now(),
              ),
            ),
          ],
        ),
      ),
    ));

    expect(find.byType(HighlightedCode), findsNothing);
  });

  testWidgets('code-like tool result is syntax highlighted',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: ListView(
          children: [
            ChatBubble(
              message: PiMessage(
                id: '1',
                role: 'assistant',
                content: '',
                timestamp: DateTime.now(),
                toolCalls: [
                  PiTool(
                    name: 'read_file',
                    arguments: const {'path': 'src/app.ts'},
                    result: '{\n  "ok": true,\n  "count": 42,\n  "items": [1, 2, 3]\n}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.byType(HighlightedCode), findsOneWidget);
  });

  testWidgets('prose tool result stays plain text', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: ListView(
          children: [
            ChatBubble(
              message: PiMessage(
                id: '1',
                role: 'assistant',
                content: '',
                timestamp: DateTime.now(),
                toolCalls: [
                  PiTool(
                    name: 'status',
                    arguments: const {},
                    result: 'Done.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.byType(HighlightedCode), findsNothing);
    expect(find.text('Done.'), findsOneWidget);
  });

  test('identical code blocks reuse the same highlight result', () {
    const code = 'const x = 1;\nfunction f() {\n  return x;\n}';

    final first = highlightedSpans(code, isDark: true);
    final again = highlightedSpans(code, isDark: true);
    expect(identical(first, again), isTrue,
        reason: 'scrolling a chat must not re-parse the same code block');

    expect(identical(first, highlightedSpans('$code\n// edited', isDark: true)),
        isFalse,
        reason: 'changed source must not hit the cache');
    expect(identical(first, highlightedSpans(code, isDark: false)), isFalse,
        reason: 'the other theme has different colours');
  });

  testWidgets('an unchanged bubble reuses its cached rendering',
      (WidgetTester tester) async {
    final message = PiMessage(
      id: '1',
      role: 'assistant',
      content: 'Some **markdown**:\n\n```python\nprint("hi")\n```\n',
      timestamp: DateTime.now(),
    );

    Widget app() => MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(body: ChatBubble(message: message)),
        );

    await tester.pumpWidget(app());
    final first = tester.widget<MarkdownBody>(find.byType(MarkdownBody));

    // A rebuild of the same message must not parse the Markdown again: the
    // cached children are handed back as the same widget instances, which is
    // what makes scrolling cheap.
    await tester.pumpWidget(app());
    final second = tester.widget<MarkdownBody>(find.byType(MarkdownBody));

    expect(identical(first, second), isTrue);
  });
}
