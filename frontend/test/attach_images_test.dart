import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/utils/image_picking.dart';
import 'package:pi_mobile_agent/widgets/attachment_tray.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';
import 'package:provider/provider.dart';

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

/// Real PNG bytes, made once, before any test runs.
///
/// `Picture.toImage` and `decodeImageFromList` complete on the real event loop.
/// Inside `testWidgets` the clock is fake, so an image decoded there waits on a
/// loop that is not turning - which is a hang that looks like a broken feature.
late Uint8List pngWide;
late Uint8List pngSmall;
late Uint8List pngChat;

const _visionModel = {
  'id': 'qwen-vision',
  'name': 'qwen 3.8 Strata',
  'provider': 'llama-server',
  'input': ['text', 'image'],
};

const _textOnlyModel = {
  'id': 'text-only',
  'name': 'Some Text Model',
  'provider': 'somewhere',
  'input': ['text'],
};

class _AttachService extends PiService {
  final _states = StreamController<PiState>.broadcast();
  final sent = <List<PiImage>>[];
  List<Map<String, dynamic>> models = const [_visionModel, _textOnlyModel];
  String currentModelId = 'qwen-vision';

  @override
  Stream<PiState> get stateUpdates => _states.stream;

  @override
  Stream<PiEvent> get events => const Stream.empty();

  @override
  bool get isConnected => true;

  @override
  Future<void> refreshState() async {}

  @override
  Future<List<PiModel>> getAvailableModels() async =>
      models.map(PiModel.fromJson).toList();

  @override
  Future<void> sendPrompt(String message,
      {List<PiImage> images = const []}) async {
    sent.add(images);
  }

  @override
  Future<PiSessionStats> getSessionStats() async =>
      PiSessionStats.fromJson(const {'tokens': {}, 'cost': 0});
}

Future<(PiViewModel, _AttachService)> pumpHome(
  WidgetTester tester, {
  String currentModelId = 'qwen-vision',
  List<Map<String, dynamic>> models = const [_visionModel, _textOnlyModel],
  List<PickedImage> picked = const [],
  bool pickerSupported = true,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final service = _AttachService()
    ..models = models
    ..currentModelId = currentModelId;
  final viewModel = PiViewModel(piService: service);
  // A test has no browser, so the device picker the app would open is replaced
  // before the first frame - otherwise the control it gates is never built and
  // the test would be checking a widget that is deliberately absent.
  viewModel.useImagePickerForTest(() async => picked,
      supported: pickerSupported);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppearanceController>(
      create: (_) => AppearanceController(),
      child: ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    ),
  );
  service._states.add(PiState(
    currentModel: currentModelId,
    currentModelProvider:
        currentModelId == 'qwen-vision' ? 'llama-server' : 'somewhere',
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return (viewModel, service);
}

FloatingActionButton attachButton(WidgetTester tester) =>
    tester.widget<FloatingActionButton>(find.ancestor(
        of: find.byIcon(Icons.add_photo_alternate_outlined),
        matching: find.byType(FloatingActionButton)));

void main() {
  setUpAll(() async {
    pngWide = await pngOf(60, 40);
    pngSmall = await pngOf(20, 20);
    pngChat = await pngOf(30, 30);
  });

  group('the attach control', () {
    testWidgets('is offered when the model can be sent an image',
        (tester) async {
      await pumpHome(tester);
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
      expect(attachButton(tester).onPressed, isNotNull);
    });

    testWidgets('is closed, and says why, when the model cannot',
        (tester) async {
      await pumpHome(tester,
          currentModelId: 'text-only',
          models: const [_textOnlyModel, _visionModel]);
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
      expect(attachButton(tester).onPressed, isNull);
    });

    testWidgets('marks which models take images where the choice is made',
        (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // A DropdownButton renders its selected item's row twice - once in the
      // closed button, once in the open menu - so "a badge on the capable
      // model, none on the other" is the honest claim to make here.
      final visionRow = find.ancestor(
        of: find.text('qwen 3.8 Strata'),
        matching: find.byType(DropdownMenuItem<String>),
      );
      final textRow = find.ancestor(
        of: find.text('Some Text Model'),
        matching: find.byType(DropdownMenuItem<String>),
      );

      expect(
        find.descendant(
            of: visionRow, matching: find.byIcon(Icons.image_outlined)),
        findsWidgets,
      );
      expect(
        find.descendant(
            of: textRow, matching: find.byIcon(Icons.image_outlined)),
        findsNothing,
      );
    });
  });

  group('attaching from the composer', () {
    testWidgets('a chosen image appears above the field before it is sent',
        (tester) async {
      final (_, _) = await pumpHome(tester,
          picked: [PickedImage(name: 'whiteboard.png', bytes: pngWide)]);

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      // Decoding an image happens on the real event loop, which the fake clock
      // does not turn: this is the harness's own way of letting it finish.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(find.byType(AttachmentTray), findsOneWidget);
      expect(find.text('whiteboard.png'), findsOneWidget);
      expect(find.textContaining('60×40'), findsOneWidget);
    });

    testWidgets('the tray takes an image back out', (tester) async {
      final (viewModel, _) = await pumpHome(tester);
      // Real image work, so it runs in the harness's real-async zone.
      await tester.runAsync(
          () => viewModel.addAttachmentBytes(bytes: pngSmall, name: 'one.png'));
      await tester.pump();

      await tester.tap(find.byTooltip('Remove image'));
      await tester.pump();

      expect(viewModel.attachments, isEmpty);
      expect(find.byType(AttachmentTray), findsNothing);
    });

    testWidgets('sending carries the image to the backend', (tester) async {
      final (viewModel, service) = await pumpHome(tester);
      // Real image work, so it runs in the harness's real-async zone.
      await tester.runAsync(
          () => viewModel.addAttachmentBytes(bytes: pngSmall, name: 'one.png'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'what does this show?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(service.sent.single.length, 1);
      expect(viewModel.attachments, isEmpty);
    });

    testWidgets('a model that cannot see images is not sent one',
        (tester) async {
      final (viewModel, service) = await pumpHome(tester,
          currentModelId: 'text-only',
          models: const [_textOnlyModel, _visionModel]);
      await tester.runAsync(
          () => viewModel.addAttachmentBytes(bytes: pngSmall, name: 'one.png'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'what does this show?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // Not sent without the image, and not sent with it silently dropped:
      // the app says why instead of choosing which half of the message to keep.
      expect(service.sent, isEmpty);
      expect(viewModel.attachments.length, 1);
      expect(find.textContaining('does not accept images'), findsOneWidget);
    });
  });

  group('the image in the chat', () {
    Future<void> pumpBubble(WidgetTester tester, PiMessage message) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [ChatBubble(message: message)]),
          ),
        ),
      );
    }

    testWidgets('a message with an image shows it', (tester) async {
      final image = PiImage(
        name: 'photo.png',
        mimeType: 'image/png',
        base64Data: base64Encode(pngChat),
        width: 30,
        height: 30,
      );
      await pumpBubble(
        tester,
        PiMessage(
          id: 'u1',
          role: 'user',
          content: 'what is this?',
          timestamp: DateTime.now(),
          images: [image],
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('what is this?'), findsOneWidget);
    });

    testWidgets('a message that is only an image is still shown',
        (tester) async {
      await pumpBubble(
        tester,
        PiMessage(
          id: 'u2',
          role: 'user',
          content: '',
          timestamp: DateTime.now(),
          images: [
            PiImage(
              name: 'photo.png',
              mimeType: 'image/png',
              base64Data: base64Encode(pngChat),
            ),
          ],
        ),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('an image the app cannot draw says so instead of vanishing',
        (tester) async {
      await pumpBubble(
        tester,
        PiMessage(
          id: 'u3',
          role: 'user',
          content: 'look',
          timestamp: DateTime.now(),
          images: [
            PiImage(
              name: 'broken.png',
              mimeType: 'image/png',
              base64Data: 'not base64 at all !!!',
            ),
          ],
        ),
      );

      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(find.text('broken.png'), findsOneWidget);
    });
  });
}
