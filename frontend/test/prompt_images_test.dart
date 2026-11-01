import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/utils/image_picking.dart';

Future<Uint8List> pngOf(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFCC3366),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A prompt recorder standing in for the backend.
class RecordingService extends PiService {
  final _events = StreamController<PiEvent>.broadcast();
  final _states = StreamController<PiState>.broadcast();

  final sent = <SentPrompt>[];
  bool failNextSend = false;
  List<Map<String, dynamic>> models = const [];

  @override
  Stream<PiEvent> get events => _events.stream;

  @override
  Stream<PiState> get stateUpdates => _states.stream;

  @override
  Future<List<PiModel>> getAvailableModels() async =>
      models.map(PiModel.fromJson).toList();

  @override
  Future<void> sendPrompt(String message,
      {List<PiImage> images = const []}) async {
    if (failNextSend) {
      failNextSend = false;
      throw Exception('backend said no');
    }
    sent.add(SentPrompt(message, images));
  }

  @override
  Future<PiSessionStats> getSessionStats() async =>
      PiSessionStats.fromJson(const {'tokens': {}, 'cost': 0});

  /// Tell the view which model Pi is answering with.
  void useModel(String id, String provider) => _states.add(
        PiState(currentModel: id, currentModelProvider: provider),
      );
}

class SentPrompt {
  final String message;
  final List<PiImage> images;

  const SentPrompt(this.message, this.images);
}

void main() {
  late RecordingService service;
  late PiViewModel viewModel;

  Future<void> start({
    List<Map<String, dynamic>> models = const [],
  }) async {
    service = RecordingService()..models = models;
    viewModel = PiViewModel(piService: service);
    // Let the model list and any state frame land before the test asks.
    await Future<void>.delayed(Duration.zero);
  }

  /// A picker standing in for the device's, which a test does not have.
  void givePicker(List<PickedImage> picked, {bool supported = true}) =>
      viewModel.useImagePickerForTest(() async => picked, supported: supported);

  final visionModels = [
    {
      'id': 'qwen-vision',
      'name': 'qwen 3.8 Strata',
      'provider': 'llama-server',
      'input': ['text', 'image'],
    },
    {
      'id': 'text-only',
      'name': 'Some Text Model',
      'provider': 'somewhere',
      'input': ['text'],
    },
  ];

  group('what a model can be shown', () {
    test('a model is asked what it accepts, from the list Pi offers', () async {
      await start(models: visionModels);
      service.useModel('qwen-vision', 'llama-server');
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.currentModel?.acceptsImages, isTrue);
      // The capability comes from Pi's `input` field, not from the model's name.
      expect(viewModel.availableModels.last.acceptsImages, isFalse);
    });

    test('a model that cannot see images closes the attach control', () async {
      await start(models: visionModels);
      givePicker(const []);
      service.useModel('text-only', 'somewhere');
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.canAttachImages, isFalse);
      expect(viewModel.attachmentUnavailableReason,
          contains('does not accept images'));
    });

    test('a model the app cannot match does not hide the feature', () async {
      await start(models: visionModels);
      service.useModel('a-model-pi-did-not-offer', 'who-knows');
      await Future<void>.delayed(Duration.zero);

      // Saying "no" here would refuse a model the app has no information about.
      expect(viewModel.currentModel, isNull);
      expect(viewModel.attachmentsAccepted, isTrue);
    });
  });

  group('attaching and sending', () {
    test('a picked image is prepared and queued', () async {
      await start(models: visionModels);
      service.useModel('qwen-vision', 'llama-server');
      final png = await pngOf(20, 20);
      givePicker([PickedImage(name: 'whiteboard.png', bytes: png)]);

      await viewModel.attachImagesFromDevice();

      expect(viewModel.attachments.length, 1);
      expect(viewModel.attachments.first.name, 'whiteboard.png');
      expect(viewModel.attachments.first.width, 20);
    });

    test('sending carries the images alongside the text', () async {
      await start(models: visionModels);
      service.useModel('qwen-vision', 'llama-server');
      givePicker([
        PickedImage(name: 'a.png', bytes: await pngOf(10, 10)),
        PickedImage(name: 'b.png', bytes: await pngOf(12, 8)),
      ]);
      await viewModel.attachImagesFromDevice();

      viewModel.setUserInput('what is in these?');
      await viewModel.submitPrompt();

      expect(service.sent.length, 1);
      expect(service.sent.first.message, 'what is in these?');
      expect(service.sent.first.images.length, 2);
      expect(service.sent.first.images.first.mimeType, 'image/png');
      // Sent, so no longer waiting to be sent.
      expect(viewModel.attachments, isEmpty);
    });

    test('the message in the chat carries them too', () async {
      await start(models: visionModels);
      service.useModel('qwen-vision', 'llama-server');
      givePicker([PickedImage(name: 'photo.png', bytes: await pngOf(10, 10))]);
      await viewModel.attachImagesFromDevice();

      viewModel.setUserInput('describe this');
      await viewModel.submitPrompt();

      final mine = viewModel.messages.last;
      expect(mine.role, 'user');
      expect(mine.images.length, 1);
    });

    test('images are not dropped quietly for a model that cannot see them',
        () async {
      await start(models: visionModels);
      service.useModel('qwen-vision', 'llama-server');
      givePicker([PickedImage(name: 'photo.png', bytes: await pngOf(10, 10))]);
      await viewModel.attachImagesFromDevice();

      // The model changes to one that cannot see, with the image still queued.
      service.useModel('text-only', 'somewhere');
      await Future<void>.delayed(Duration.zero);

      viewModel.setUserInput('describe this');
      await viewModel.submitPrompt();

      expect(service.sent, isEmpty);
      expect(viewModel.attachments.length, 1);
      expect(viewModel.error, contains('does not accept images'));
      // The text is still there to send once the model is changed.
      expect(viewModel.userInput, 'describe this');
    });

    test('a send that failed keeps the images where the user can see them',
        () async {
      await start(models: visionModels);
      service.useModel('qwen-vision', 'llama-server');
      givePicker([PickedImage(name: 'photo.png', bytes: await pngOf(10, 10))]);
      await viewModel.attachImagesFromDevice();
      service.failNextSend = true;

      viewModel.setUserInput('describe this');
      await viewModel.submitPrompt();

      expect(viewModel.attachments.length, 1);
      expect(viewModel.error, contains('backend said no'));
    });

    test('taking one back out works', () async {
      await start(models: visionModels);
      service.useModel('qwen-vision', 'llama-server');
      givePicker([
        PickedImage(name: 'keep.png', bytes: await pngOf(10, 10)),
        PickedImage(name: 'drop.png', bytes: await pngOf(10, 10)),
      ]);
      await viewModel.attachImagesFromDevice();

      viewModel.removeAttachmentAt(1);

      expect(viewModel.attachments.length, 1);
      expect(viewModel.attachments.first.name, 'keep.png');
    });

    test('an image the app cannot prepare is refused with its reason',
        () async {
      await start(models: visionModels);
      service.useModel('qwen-vision', 'llama-server');
      givePicker([
        PickedImage(
          name: 'IMG_0042.HEIC',
          bytes: Uint8List.fromList([
            0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70, // "ftyp"
            0x68, 0x65, 0x69, 0x63, // "heic"
            ...List.filled(32, 0),
          ]),
        ),
      ]);

      await viewModel.attachImagesFromDevice();

      expect(viewModel.attachments, isEmpty);
      expect(viewModel.error, contains('HEIC'));
    });

    test('a build with no picker does not offer one', () async {
      await start(models: visionModels);
      service.useModel('qwen-vision', 'llama-server');
      givePicker(const [], supported: false);

      expect(viewModel.canAttachImages, isFalse);
      expect(viewModel.attachmentUnavailableReason,
          contains('cannot open the device'));
    });

    test('a prompt with no image attached is sent the way it always was',
        () async {
      await start(models: visionModels);
      service.useModel('qwen-vision', 'llama-server');

      viewModel.setUserInput('just text');
      await viewModel.submitPrompt();

      expect(service.sent.single.images, isEmpty);
    });
  });
}
