import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';

/// Stands in for the clipboard so a selection can be checked by what it copies.
/// "Select across the whole reply" is a claim about what ends up in the
/// clipboard, and that is observable; a highlighted rectangle is not.
class _FakeClipboard {
  final List<String> copied = [];

  Future<Object?> handle(MethodCall call) async {
    if (call.method != 'Clipboard.setData') return null;
    copied.add((call.arguments as Map)['text'] as String);
    return null;
  }
}

PiMessage _reply(String content) => PiMessage(
      id: 'm1',
      role: 'assistant',
      content: content,
      timestamp: DateTime.utc(2026, 1, 1),
    );

/// A reply whose text is split across the kinds of block a real answer has.
/// The point of every test here is the span from the first line to the last:
/// that is what someone wants to copy, and it is what a reply rendered as one
/// selectable field per block cannot give.
const multiBlock = '''The first paragraph says alpha.

```dart
const betaValue = 1;
```

The last paragraph says gamma.
''';

Future<void> _pump(WidgetTester tester, PiMessage message,
    [_FakeClipboard? clipboard]) async {
  if (clipboard != null) {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, clipboard.handle);
  }
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ChatBubble(message: message))),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('selecting a reply', () {
    testWidgets('the whole reply is one selection, not a field per block',
        (tester) async {
      await _pump(tester, _reply(multiBlock));

      final area = find.byType(SelectionArea);
      expect(area, findsOneWidget);

      // The blocks are plain Text, which joins the selection area it sits in.
      // `MarkdownBody(selectable: true)` builds a SelectableText - a read-only
      // text field with its own focus and its own selection - for every
      // paragraph, fence and heading, and a drag cannot cross a field boundary.
      expect(
        find.descendant(of: area, matching: find.byType(SelectableText)),
        findsNothing,
      );

      final blocks = tester.elementList(
          find.descendant(of: area, matching: find.byType(Text)).first);
      final all = tester
          .widgetList(find.descendant(of: area, matching: find.byType(Text)));
      expect(all.length, greaterThan(1),
          reason: 'the fixture is only worth anything if it really is several '
              'blocks, which is the case the old rendering could not select');

      final registrars = <Object?>[
        for (final widget in all)
          SelectionContainer.maybeOf(
              tester.element(find.byWidget(widget, skipOffstage: false))),
      ];
      expect(registrars.first, isNotNull);
      for (final registrar in registrars) {
        expect(identical(registrar, registrars.first), isTrue,
            reason:
                'every block resolves to the same selection registry, which '
                'is what makes one drag reach across them');
      }
      expect(blocks, isNotNull);
    });

    testWidgets('a selection taken across the reply copies all of it',
        (tester) async {
      final clipboard = _FakeClipboard();
      await _pump(tester, _reply(multiBlock), clipboard);

      final region = tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion;

      region.selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      // The intent Ctrl+C dispatches, rather than the deprecated
      // `copySelection` method.
      Actions.invoke(
        tester.element(find
            .descendant(
              of: find.byType(SelectionArea),
              matching: find.byType(Text),
            )
            .first),
        CopySelectionTextIntent.copy,
      );
      await tester.pump();

      expect(clipboard.copied.length, 1);
      final text = clipboard.copied.single;

      expect(text, contains('The first paragraph says alpha.'));
      expect(text, contains('betaValue'));
      expect(text, contains('The last paragraph says gamma.'),
          reason: 'a selection that starts in a paragraph and ends past a '
              'fenced block is the thing a chat reader actually wants, and it '
              'is what per-block selection cannot produce');
    });

    testWidgets('the controls in the bubble are not part of the text',
        (tester) async {
      await _pump(tester, _reply('a reply with something to copy'));

      final area = find.byType(SelectionArea);
      expect(
        find.descendant(of: area, matching: find.byType(IconButton)),
        findsNothing,
        reason: 'dragging over a bubble should not try to select its copy '
            'button, and the header is not text anyone is asking for',
      );
      expect(
          find.descendant(of: area, matching: find.text('Pi')), findsNothing);
    });

    testWidgets(
        'tool output is selectable too, because it is the text worth '
        'copying off a phone', (tester) async {
      final message = PiMessage(
        id: 'm1',
        role: 'assistant',
        content: '',
        timestamp: DateTime.utc(2026, 1, 1),
        toolCalls: [
          PiTool(
            name: 'exec',
            arguments: const {'command': 'git status --short'},
            result: ' M src/index.ts',
          ),
        ],
      );
      final clipboard = _FakeClipboard();
      await _pump(tester, message, clipboard);

      final region = tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion;
      region.selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      Actions.invoke(
        tester.element(find
            .descendant(
              of: find.byType(SelectionArea),
              matching: find.byType(Text),
            )
            .first),
        CopySelectionTextIntent.copy,
      );
      await tester.pump();

      final copied = clipboard.copied.join('\n');
      expect(copied, contains('git status --short'));
      expect(copied, contains('src/index.ts'));
    });
  });
}
