import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/utils/image_attachment.dart';

/// A real PNG of the requested size.
///
/// Hand-written headers would test what this code assumes about a file format;
/// drawing a picture and encoding it tests what it actually does with one.
Future<Uint8List> pngOf(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

/// A stand-in for what an iPhone camera hands a file input.
Uint8List heicBytes() => bytes([
      0x00, 0x00, 0x00, 0x1C, // box size
      0x66, 0x74, 0x79, 0x70, // "ftyp"
      0x68, 0x65, 0x69, 0x63, // "heic"
      0x00, 0x00, 0x00, 0x00,
      ...List.filled(64, 0x00),
    ]);

void main() {
  group('recognising what a file actually is', () {
    test('PNG, JPEG, GIF and WebP are named from their own bytes', () {
      expect(sniffImageMime(bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), 'image/png');
      expect(sniffImageMime(bytes([0xFF, 0xD8, 0xFF, 0xDB])), 'image/jpeg');
      expect(sniffImageMime(bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])), 'image/gif');
      expect(
        sniffImageMime(bytes([
          0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, // "RIFF" + size
          0x57, 0x45, 0x42, 0x50, // "WEBP"
        ])),
        'image/webp',
      );
    });

    test('a file that is not an image has no type', () {
      expect(sniffImageMime(bytes([0x25, 0x50, 0x44, 0x46])), isNull); // a PDF
      expect(sniffImageMime(bytes([0x00, 0x01, 0x02, 0x03])), isNull);
    });
  });

  group('preparing a picked image', () {
    test('an image that already fits is sent as it was picked', () async {
      final original = await pngOf(40, 30);

      final prepared =
          await preparePickedImage(bytes: original, name: 'note.png');

      expect(prepared.mimeType, 'image/png');
      expect(prepared.width, 40);
      expect(prepared.height, 30);
      // Byte for byte: re-encoding something the model can already read would
      // cost quality for nothing.
      expect(base64Decode(prepared.base64Data), original);
    });

    test('the type comes from the bytes, not from the name', () async {
      final png = await pngOf(16, 16);

      final prepared = await preparePickedImage(bytes: png, name: 'photo.jpg');

      expect(prepared.mimeType, 'image/png');
    });

    test('a photo larger than the edge is rescaled to it', () async {
      final original = await pngOf(2000, 1500);

      final prepared = await preparePickedImage(bytes: original, name: 'IMG_1.png');

      expect(prepared.width, defaultMaxEdge);
      expect(prepared.height, 768); // the shape of the photo is kept
      expect(base64Decode(prepared.base64Data).length,
          lessThan(original.length));
    });

    test('a square is resized on its longest edge only', () async {
      final prepared = await preparePickedImage(
        bytes: await pngOf(1200, 1200),
        name: 'square.png',
      );

      expect(prepared.width, defaultMaxEdge);
      expect(prepared.height, defaultMaxEdge);
    });

    test('resizing keeps trying smaller until the payload fits', () async {
      // Small enough that the 1024 attempt is refused and 768 is used.
      final original = await pngOf(1600, 1200);

      final prepared = await preparePickedImage(
        bytes: original,
        name: 'plan.png',
        maxBytes: 4000,
      );

      expect(prepared.width, 768);
      expect(prepared.height, 576);
    });

    test('an image no size in the ladder can make small enough is refused',
        () async {
      final original = await pngOf(1600, 1200);

      await expectLater(
        preparePickedImage(bytes: original, name: 'huge.png', maxBytes: 200),
        throwsA(isA<ImageAttachmentError>().having(
            (error) => error.message, 'message', contains('too large to send'))),
      );
    });

    test('an empty file is refused', () async {
      await expectLater(
        preparePickedImage(bytes: bytes([]), name: 'empty.png'),
        throwsA(isA<ImageAttachmentError>()
            .having((error) => error.message, 'message', contains('empty'))),
      );
    });

    test('a HEIC is refused with the advice an iPhone user can act on',
        () async {
      await expectLater(
        preparePickedImage(bytes: heicBytes(), name: 'IMG_0042.HEIC'),
        throwsA(isA<ImageAttachmentError>().having(
            (error) => error.message, 'message', allOf(contains('HEIC'), contains('JPEG')))),
      );
    });

    test('a file that is not an image says which formats work', () async {
      await expectLater(
        preparePickedImage(bytes: bytes([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]), name: 'spec.pdf'),
        throwsA(isA<ImageAttachmentError>().having((error) => error.message,
            'message', contains('PNG, JPEG, GIF or WebP'))),
      );
    });
  });

  group('the payload a prompt carries', () {
    test('an image serialises in the shape Pi takes', () async {
      final prepared = await preparePickedImage(
        bytes: await pngOf(8, 8),
        name: 'small.png',
      );

      final json = prepared.toJson();
      expect(json['type'], 'image');
      expect(json['mimeType'], 'image/png');
      // No `data:` prefix: Pi wants the base64 on its own.
      expect(json['data'], isNot(startsWith('data:')));
      expect(base64Decode(json['data'] as String), isNotEmpty);
    });

    test('an image read back out of a transcript keeps its payload', () {
      final image = PiImage.fromContentBlock({
        'type': 'image',
        'data': base64Encode([0xFF, 0xD8, 0xFF]),
        'mimeType': 'image/jpeg',
      });

      expect(image, isA<PiImage>());
      expect(image!.mimeType, 'image/jpeg');
      expect(image.sizeLabel, '3 B');
    });

    test('a text block is not mistaken for an image', () {
      expect(PiImage.fromContentBlock({'type': 'text', 'text': 'hello'}), isNull);
      expect(PiImage.fromContentBlock('nonsense'), isNull);
    });
  });
}
