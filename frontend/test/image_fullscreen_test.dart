import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';

Future<Uint8List> pngOf(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF227755),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Real PNG bytes, made before any test runs: `toImage` completes on the real
/// event loop, which `testWidgets` does not have.
late String pngBase64;

PiImage attached({String name = 'photo.png'}) =>
    PiImage(name: name, mimeType: 'image/png', base64Data: pngBase64);

PiMessage withImage() => PiMessage(
      id: 'a1',
      role: 'user',
      content: 'what is in this picture?',
      timestamp: DateTime(2026),
      images: [attached()],
    );

PiMessage toolImage() => PiMessage(
      id: 'a2',
      role: 'assistant',
      content: '',
      timestamp: DateTime(2026),
      toolCalls: [
        PiTool(
          name: 'codemode',
          arguments: const {'script': 'image(block)'},
          result: '==> image 1/1 <==\n/tmp/pi-image-7f3a.png',
          images: [attached(name: 'image 1')],
        ),
      ],
    );

/// A chat on a screen of [size], so "full screen" can be measured against the
/// screen it was opened on.
Future<void> pumpChat(WidgetTester tester, PiMessage message, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ListView(children: [ChatBubble(message: message)]),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 120));
}

Finder _thumbnail(WidgetTester tester) => find
    .descendant(of: find.byType(ChatBubble), matching: find.byType(Image))
    .first;

Finder _openedImage() =>
    find.descendant(of: find.byType(Dialog), matching: find.byType(Image));

/// Tap the thumbnail the way a thumb does, in its middle.
Future<void> openImage(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(_thumbnail(tester)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    pngBase64 = base64Encode(await pngOf(40, 40));
  });

  group('a picture in the chat, opened', () {
    testWidgets('fills the phone it was opened on', (tester) async {
      const screen = Size(390, 844);
      await pumpChat(tester, withImage(), screen);

      final thumbnail = tester.getRect(_thumbnail(tester));
      await openImage(tester);

      final dialog = tester.getRect(find.byType(Dialog));
      expect(dialog.width, closeTo(screen.width, 1));
      expect(dialog.height, closeTo(screen.height, 1),
          reason: 'a bounded dialog leaves a strip of chat visible beside it, '
              'which is the screen the picture is not using');

      final opened = tester.getRect(_openedImage());
      expect(opened.width, greaterThan(thumbnail.width * 2),
          reason: 'the reason the thumbnail was tapped is that it is unreadable. '
              'A slightly larger version of it does not answer that');
    });

    testWidgets('is not capped at the size the old dialog allowed',
        (tester) async {
      // The viewer used to wrap the picture in maxWidth 900 / maxHeight 700, so
      // on a wide screen it stopped there while the chat kept scrolling.
      const screen = Size(1400, 1000);
      await pumpChat(tester, withImage(), screen);

      await openImage(tester);

      final opened = tester.getRect(_openedImage());
      expect(opened.width, greaterThan(900));
      expect(opened.height, greaterThan(700));
    });

    testWidgets('a tool picture opens in the same viewer', (tester) async {
      const screen = Size(390, 844);
      await pumpChat(tester, toolImage(), screen);

      await openImage(tester);

      expect(_openedImage(), findsOneWidget,
          reason: 'a picture the agent produced and one the user sent are the '
              'same thing to look at. A second viewer for one of them is a '
              'second rule for the same thing');
      expect(tester.getRect(find.byType(Dialog)).width,
          closeTo(screen.width, 1));
    });

    testWidgets('still opens after the bubble came back out of the body cache',
        (tester) async {
      // A bubble body is a cached subtree, so the second time this message is on
      // screen the widgets are the ones built the first time - mounted on new
      // elements, with the old elements gone. A tap handler written by the
      // bubble's own build would be holding one of those, and the picture would
      // open on a context that no longer exists.
      const screen = Size(390, 844);
      await pumpChat(tester, withImage(), screen);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpChat(tester, withImage(), screen);

      await openImage(tester);

      expect(_openedImage(), findsOneWidget);
      expect(tester.getRect(find.byType(Dialog)).width, closeTo(screen.width, 1));
    });

    testWidgets('closes from its own control', (tester) async {
      await pumpChat(tester, withImage(), const Size(390, 844));
      await openImage(tester);

      // A full-screen dialog covers the modal barrier, so there is no outside
      // left to tap: the way out has to be inside.
      await tester.tap(find.byTooltip('Close image'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_openedImage(), findsNothing);
      expect(find.byType(ChatBubble), findsOneWidget,
          reason: 'closing the picture returns to the conversation it came from');
    });

    testWidgets('closes with Escape, which is the barrier still listening',
        (tester) async {
      await pumpChat(tester, withImage(), const Size(1400, 1000));
      await openImage(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_openedImage(), findsNothing);
    });

    testWidgets('zooms rather than being capped at the screen', (tester) async {
      await pumpChat(tester, withImage(), const Size(390, 844));
      await openImage(tester);

      expect(find.byType(InteractiveViewer), findsOneWidget,
          reason: 'full screen is the largest the screen can show, not the size '
              'the file was drawn at. A screenshot of a log is read by zooming');
    });
  });
}
