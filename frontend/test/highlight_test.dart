import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
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

    // The HighlightView widget should be present in the tree.
    expect(find.byType(HighlightView), findsOneWidget);

    // The highlighted code should be rendered as RichText spans, not plain text.
    final richTexts = find.byType(RichText);
    expect(richTexts, findsWidgets);
  });

  testWidgets('code fence without a language tag still renders safely',
      (WidgetTester tester) async {
    // highlight.parse throws when language is null, so bare fences must be
    // resolved to a concrete language instead of crashing the bubble.
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
    expect(find.byType(HighlightView), findsOneWidget);
  });

  testWidgets('plain text without fences does not use HighlightView',
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

    expect(find.byType(HighlightView), findsNothing);
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
    expect(find.byType(HighlightView), findsOneWidget);
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
    expect(find.byType(HighlightView), findsNothing);
    expect(find.text('Done.'), findsOneWidget);
  });
}
