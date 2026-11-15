import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/utils/code_highlight.dart';
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

/// PiService stub that replays canned backend frames instead of a WebSocket.
class FakePiService extends PiService {
  final _events = StreamController<PiEvent>.broadcast();
  @override
  Stream<PiState> get stateUpdates => const Stream.empty();
  @override
  Stream<PiEvent> get events => _events.stream;

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));
}

/// PiService stub whose resume returns a canned saved transcript.
class FakeResumeService extends FakePiService {
  final List<Map<String, dynamic>> history;
  FakeResumeService(this.history);

  @override
  Future<List<Map<String, dynamic>>> resumeSession(String sessionPath) async =>
      history;
}

/// What a `codemode` script that drew something looks like on the wire: text and
/// image blocks in one result, the text naming the file the image was saved to.
Map<String, dynamic> paintedResult({int images = 1, bool withText = true}) => {
      'content': [
        if (withText) ...[
          {'type': 'text', 'text': 'Script completed in 4.2s'},
          {
            'type': 'text',
            'text': '==> image 1/$images <==\n/tmp/pi-image-7f3a.png',
          },
        ],
        for (var i = 0; i < images; i++)
          {'type': 'image', 'data': pngBase64, 'mimeType': 'image/png'},
      ],
    };

/// The frames of one tool call, from the model asking for it to it finishing.
void runToolCall(FakePiService service, Map<String, dynamic> result,
    {String toolName = 'codemode', String callId = 'toolu_img'}) {
  service.emit({
    'type': 'message_start',
    'message': {
      'role': 'assistant',
      'content': [
        {
          'type': 'toolCall',
          'id': callId,
          'name': toolName,
          'arguments': {'script': 'image(block)'},
        }
      ],
    },
  });
  service.emit({
    'type': 'tool_execution_start',
    'toolCallId': callId,
    'toolName': toolName,
    'args': {'script': 'image(block)'},
  });
  service.emit({
    'type': 'tool_execution_end',
    'toolCallId': callId,
    'toolName': toolName,
    'result': result,
  });
  service.emit({
    'type': 'message_end',
    'message': {'role': 'assistant', 'content': []},
  });
  service.emit({'type': 'agent_end', 'messages': []});
}

PiTool onlyTool(PiViewModel vm) => vm.messages.last.toolCalls.single;

/// Whether a string is drawn anywhere in what is on screen - as a `Text`, or as
/// the source of a highlighted block. A tool result is one or the other depending
/// on whether it looks like code, and a test that only looks for one passes over
/// the case it is not looking at.
bool _shows(WidgetTester tester, String needle) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
      .toList();
  final code = tester
      .widgetList<HighlightedCode>(find.byType(HighlightedCode))
      .map((w) => w.source)
      .toList();
  return [...texts, ...code].any((s) => s.contains(needle));
}

Future<void> pumpBubble(WidgetTester tester, PiMessage message,
    {bool compact = false}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [ChatBubble(message: message, compact: compact)],
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 120));
}

PiMessage toolMessage(List<PiTool> tools, {String content = ''}) => PiMessage(
      id: 'a1',
      role: 'assistant',
      content: content,
      timestamp: DateTime(2026),
      toolCalls: tools,
    );

void main() {
  setUpAll(() async {
    pngBase64 = base64Encode(await pngOf(40, 40));
  });

  group('a tool result that carries an image', () {
    test('the image is read out of the result, next to its text', () async {
      final service = FakePiService();
      final vm = PiViewModel(piService: service);

      runToolCall(service, paintedResult());
      await pumpEventQueue();

      final tool = onlyTool(vm);
      expect(tool.result, contains('Script completed'),
          reason: 'the text half is what the model is shown, and it is still '
              "the half the card prints");
      expect(tool.images.length, 1);
      expect(tool.images.single.mimeType, 'image/png');
      expect(base64Decode(tool.images.single.base64Data), isNotEmpty);

      vm.dispose();
    });

    test('a result that is only an image is still read', () async {
      final service = FakePiService();
      final vm = PiViewModel(piService: service);

      runToolCall(service, paintedResult(withText: false),
          toolName: 'read', callId: 'toolu_read');
      await pumpEventQueue();

      expect(onlyTool(vm).images.length, 1);
      expect(onlyTool(vm).result, isEmpty,
          reason: 'there is no text in that result. Drawing the picture is the '
              'whole of what it returned');

      vm.dispose();
    });

    test('several images from one call are named apart', () async {
      final service = FakePiService();
      final vm = PiViewModel(piService: service);

      runToolCall(service, paintedResult(images: 3));
      await pumpEventQueue();

      final images = onlyTool(vm).images;
      expect(images.length, 3);
      expect(images.map((image) => image.name),
          ['image 1', 'image 2', 'image 3'],
          reason: 'a name is only read when an image will not draw, and three '
              'placeholders all saying "image" is nothing to tell apart');

      vm.dispose();
    });

    test('a partial result does not invent one', () async {
      final service = FakePiService();
      final vm = PiViewModel(piService: service);

      service.emit({
        'type': 'message_start',
        'message': {
          'role': 'assistant',
          'content': [
            {
              'type': 'toolCall',
              'id': 'toolu_partial',
              'name': 'bash',
              'arguments': {'command': 'convert a.png b.png'},
            }
          ],
        },
      });
      service.emit({
        'type': 'tool_execution_start',
        'toolCallId': 'toolu_partial',
        'toolName': 'bash',
        'args': {'command': 'convert a.png b.png'},
      });
      service.emit({
        'type': 'tool_execution_update',
        'toolCallId': 'toolu_partial',
        'toolName': 'bash',
        'args': {'command': 'convert a.png b.png'},
        'partialResult': {'content': [{'type': 'text', 'text': 'writing'}]},
      });
      service.emit({
        'type': 'tool_execution_end',
        'toolCallId': 'toolu_partial',
        'toolName': 'bash',
        'result': {
          'content': [
            {'type': 'text', 'text': 'wrote b.png'}
          ]
        },
      });
      service.emit({
        'type': 'message_end',
        'message': {'role': 'assistant', 'content': []},
      });
      service.emit({'type': 'agent_end', 'messages': []});
      await pumpEventQueue();

      expect(onlyTool(vm).images, isEmpty);
      expect(onlyTool(vm).result, 'wrote b.png');

      vm.dispose();
    });

    test('a resumed conversation shows the picture its tool result had',
        () async {
      final service = FakeResumeService([
        {
          'role': 'assistant',
          'timestamp': 1,
          'content': [
            {
              'type': 'toolCall',
              'id': 'toolu_old',
              'name': 'codemode',
              'arguments': {'script': 'image(block)'},
            }
          ],
        },
        {
          'role': 'toolResult',
          'toolCallId': 'toolu_old',
          'toolName': 'codemode',
          'content': [
            {'type': 'text', 'text': 'Script completed'},
            {'type': 'image', 'data': pngBase64, 'mimeType': 'image/png'},
          ],
        },
      ]);
      final vm = PiViewModel(piService: service);

      await vm.resumeSession('/sessions/painted.jsonl');

      final tool = onlyTool(vm);
      expect(tool.result, 'Script completed');
      expect(tool.images.length, 1,
          reason: 'the image is stored in the same content array as the text, '
              'and a resumed run that had a picture in it has to show it');

      vm.dispose();
    });
  });

  group('the picture in the chat', () {
    testWidgets('a tool card draws the image it returned, above its output',
        (tester) async {
      await pumpBubble(
        tester,
        toolMessage([
          PiTool(
            name: 'codemode',
            arguments: const {'script': 'image(block)'},
            result: 'Script completed in 4.2s',
            images: [
              PiImage(
                  name: 'image', mimeType: 'image/png', base64Data: pngBase64),
            ],
          ),
        ]),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('codemode'), findsOneWidget);
      expect(find.text('output'), findsOneWidget,
          reason: 'the text half is still there - this adds the picture to the '
              'card, it does not replace the exchange the card is for');

      final image = tester.getRect(find.byType(Image));
      final card = tester.getRect(find.text('output'));
      expect(image.top, lessThan(card.top),
          reason: 'a generated picture is the thing that was asked for, and the '
              'text beside it is the note on it');
    });

    testWidgets('a result that is only an image draws it without an empty output',
        (tester) async {
      await pumpBubble(
        tester,
        toolMessage([
          PiTool(
            name: 'read',
            arguments: const {'path': 'photo.png'},
            result: '',
            images: [
              PiImage(
                  name: 'image', mimeType: 'image/png', base64Data: pngBase64),
            ],
          ),
        ]),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('output'), findsNothing,
          reason: 'there is no output to label. An empty block under a read is '
              'a heading for nothing');
    });

    testWidgets('the compact view keeps the picture', (tester) async {
      await pumpBubble(
        tester,
        toolMessage([
          PiTool(
            name: 'codemode',
            arguments: const {'script': 'image(block)'},
            result: 'Script completed in 4.2s',
            images: [
              PiImage(
                  name: 'image', mimeType: 'image/png', base64Data: pngBase64),
            ],
          ),
        ]),
        compact: true,
      );

      expect(find.byType(Image), findsOneWidget,
          reason: 'what the compact view keeps off the screen is the mechanics '
              'of a call. A picture the agent made is not mechanics - it is '
              'what the call produced');
    });

    testWidgets('an image that will not draw says so inside the card', (tester) async {
      await pumpBubble(
        tester,
        toolMessage([
          PiTool(
            name: 'codemode',
            arguments: const {'script': 'image(block)'},
            result: 'Script completed',
            images: [
              PiImage(
                  name: 'image 1',
                  mimeType: 'image/png',
                  base64Data: 'not base64 at all !!!'),
            ],
          ),
        ]),
      );

      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(find.text('image 1'), findsOneWidget);
    });

    testWidgets('a tool result with no image is drawn exactly as it was',
        (tester) async {
      await pumpBubble(
        tester,
        toolMessage([
          PiTool(
            name: 'bash',
            arguments: const {'command': 'ls'},
            result: 'file1\nfile2',
          ),
        ]),
      );

      expect(find.byType(Image), findsNothing);
      expect(_shows(tester, 'file1'), isTrue,
          reason: 'a command and what it printed are the shape this card has '
              'always had. Nothing here changes one that returned no picture');
    });
  });
}
