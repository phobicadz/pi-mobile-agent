import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';

/// Stands in for the clipboard: records what the app asked to copy, and can make
/// the copy fail the way a browser does when it has no Clipboard API.
class _FakeClipboard {
  final List<String> copied = [];
  bool fails = false;

  Future<Object?> handle(MethodCall call) async {
    if (call.method != 'Clipboard.setData') return null;
    if (fails) {
      throw PlatformException(
        code: 'copy_fail',
        message: 'Clipboard is not available in the context.',
      );
    }
    copied.add((call.arguments as Map)['text'] as String);
    return null;
  }
}

PiMessage _assistant(String content) => PiMessage(
      id: 'm1',
      role: 'assistant',
      content: content,
      timestamp: DateTime.utc(2026, 1, 1),
    );

Future<void> _pump(
    WidgetTester tester, PiMessage message, _FakeClipboard clipboard) async {
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, clipboard.handle);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ChatBubble(message: message))),
  );
}

void main() {
  group('copyableText', () {
    test('is the reply text when there is one', () {
      expect(_assistant('Hello world').copyableText, 'Hello world');
    });

    test('falls back to the tool calls a tool-only bubble actually shows', () {
      final message = PiMessage(
        id: 'm1',
        role: 'assistant',
        content: '',
        timestamp: DateTime.utc(2026, 1, 1),
        toolCalls: [
          PiTool(
            name: 'read',
            arguments: const {'path': 'index.ts'},
            result: 'console.log(1);',
          ),
        ],
      );
      expect(message.copyableText, 'read(path: index.ts)\nconsole.log(1);');
    });

    test('is empty when the bubble has nothing in it', () {
      expect(
        PiMessage(
          id: 'm1',
          role: 'assistant',
          content: '',
          timestamp: DateTime.utc(2026, 1, 1),
          streaming: true,
        ).copyableText,
        isEmpty,
      );
    });
  });

  group('copy button', () {
    testWidgets('copies the reply and confirms with a toast', (tester) async {
      final clipboard = _FakeClipboard();
      await _pump(tester, _assistant('Hello world'), clipboard);

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump(const Duration(milliseconds: 100));

      expect(clipboard.copied, ['Hello world']);
      expect(find.text('Copied to clipboard'), findsOneWidget);
    });

    testWidgets('copies a user message too', (tester) async {
      final clipboard = _FakeClipboard();
      await _pump(
        tester,
        PiMessage(
          id: 'm1',
          role: 'user',
          content: 'list the files',
          timestamp: DateTime.utc(2026, 1, 1),
        ),
        clipboard,
      );

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump(const Duration(milliseconds: 100));

      expect(clipboard.copied, ['list the files']);
    });

    testWidgets('says so when the browser refuses to copy', (tester) async {
      final clipboard = _FakeClipboard()..fails = true;
      await _pump(tester, _assistant('Hello world'), clipboard);

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump(const Duration(milliseconds: 100));

      expect(clipboard.copied, isEmpty);
      expect(find.textContaining('Copy failed'), findsOneWidget);
      expect(find.text('Copied to clipboard'), findsNothing);
    });

    testWidgets('is not offered for a bubble with nothing to copy',
        (tester) async {
      await _pump(
        tester,
        PiMessage(
          id: 'm1',
          role: 'assistant',
          content: '',
          timestamp: DateTime.utc(2026, 1, 1),
          streaming: true,
        ),
        _FakeClipboard(),
      );

      expect(find.byIcon(Icons.content_copy), findsNothing);
    });

    testWidgets('sits in the top-right corner, clear of the reply text',
        (tester) async {
      await _pump(tester, _assistant('Hello world'), _FakeClipboard());

      final button = find.byType(IconButton);
      // The bubble's own box, not the ChatBubble widget: that one is an Align
      // filling the row.
      final bubble =
          find.ancestor(of: button, matching: find.byType(Container)).first;
      final bubbleRect = tester.getRect(bubble);
      final buttonRect = tester.getRect(button);

      // Top-right corner, inside the bubble's 12 x 8 padding.
      expect(buttonRect.right,
          moreOrLessEquals(bubbleRect.right - 12, epsilon: 1));
      expect(buttonRect.top, moreOrLessEquals(bubbleRect.top + 8, epsilon: 1));
      // It lives in the header band, so nothing it can cover: the label stops
      // short of it and the reply starts underneath.
      expect(tester.getRect(find.text('Pi')).right,
          lessThanOrEqualTo(buttonRect.left));
      expect(tester.getTopLeft(find.text('Hello world')).dy,
          greaterThanOrEqualTo(buttonRect.bottom));
    });
  });
}
