import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/pi_models.dart';

/// A rejected image, said in terms of what to do about it.
///
/// The app shows this text directly, so it is written as advice rather than a
/// failure: "HEIC - re-save as JPEG" is actionable, "decode failed" is not.
class ImageAttachmentError implements Exception {
  final String message;
  ImageAttachmentError(this.message);

  @override
  String toString() => message;
}

/// Longest edge an attached image keeps when it has to be re-encoded.
///
/// Vision models turn an image into a fixed number of tokens based on its
/// dimensions, so a 4000x3000 phone photo costs the same understanding as a
/// 1024px one and many times the bytes over the wire.
const int defaultMaxEdge = 1024;

/// Sizes to try, largest first, when an image has to be shrunk to fit.
const List<int> _edgeLadder = [1024, 768, 512];

/// The largest image payload the app is willing to put in a prompt.
const int defaultMaxBytes = 4 * 1024 * 1024;

/// Number of images one prompt may carry.
const int maxImagesPerPrompt = 8;

/// The types this app will attach, sniffed from the bytes.
///
/// The name the browser reports is not evidence of anything: iOS hands a
/// `.HEIC` to a file input, and a renamed `.jpg` can be a PNG. The magic bytes
/// are the only claim worth trusting here.
String? sniffImageMime(Uint8List bytes) {
  bool at(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (at(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (at(0, [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, [0x47, 0x49, 0x46, 0x38])) return 'image/gif'; // GIF87a / GIF89a
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  return null;
}

/// True for an image this app cannot send, with the reason named.
///
/// HEIC deserves its own message because it is what an iPhone camera produces,
/// so "the app rejected my photo" almost always means exactly this.
String? _unsupportedReason(Uint8List bytes) {
  final isMp4BrandContainer = bytes.length > 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70; // "ftyp"
  if (isMp4BrandContainer) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    if (brand.startsWith('hei') || brand == 'mif1' || brand == 'msph') {
      return 'HEIC. iPhone cameras save photos as HEIC; switch the camera to '
          'Format ▸ Most Compatible, or re-save the photo as JPEG.';
    }
    return brand;
  }
  return null;
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final completer = Completer<ui.Image>();
  try {
    ui.decodeImageFromList(bytes, completer.complete);
  } catch (error) {
    completer.completeError(ImageAttachmentError(
      'That file could not be read as an image (${error.toString().split(':').first}).',
    ));
  }
  return completer.future;
}

/// Redraw [source] inside [edge] pixels and encode the result as PNG.
Future<_EncodedImage> _encodeWithinEdge(ui.Image source, int edge) async {
  final longest = math.max(source.width, source.height);
  final scale = longest <= edge ? 1.0 : edge / longest;
  final width = (source.width * scale).round().clamp(1, edge);
  final height = (source.height * scale).round().clamp(1, edge);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );

  final picture = recorder.endRecording();
  try {
    final scaled = await picture.toImage(width, height);
    final encoded = await scaled.toByteData(format: ui.ImageByteFormat.png);
    if (encoded == null) {
      throw ImageAttachmentError('Could not encode the resized image.');
    }
    return _EncodedImage(
      bytes: encoded.buffer.asUint8List(),
      width: scaled.width,
      height: scaled.height,
    );
  } finally {
    picture.dispose();
  }
}

class _EncodedImage {
  final Uint8List bytes;
  final int width;
  final int height;

  const _EncodedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });
}

/// Turn bytes the user picked into something a prompt can carry.
///
/// An image that already fits is passed through untouched: re-encoding a JPEG
/// the model can already read costs quality for nothing. Only one that is too
/// big or too large in pixels is rescaled, and the resize ladder keeps trying
/// smaller sizes rather than failing on the first one.
Future<PiImage> preparePickedImage({
  required Uint8List bytes,
  required String name,
  int maxEdge = defaultMaxEdge,
  int maxBytes = defaultMaxBytes,
}) async {
  if (bytes.isEmpty) throw ImageAttachmentError('"$name" is empty.');

  final sniffed = sniffImageMime(bytes);
  if (sniffed == null) {
    final reason = _unsupportedReason(bytes);
    throw ImageAttachmentError(reason == null
        ? '"$name" is not an image this app can send. Use PNG, JPEG, GIF or WebP.'
        : '"$name" is $reason');
  }

  final ui.Image decoded;
  try {
    decoded = await _decode(bytes);
  } catch (error) {
    if (error is ImageAttachmentError) rethrow;
    throw ImageAttachmentError(
        '"$name" is not an image that can be read: $error');
  }

  try {
    final fitsUnchanged = bytes.length <= maxBytes &&
        math.max(decoded.width, decoded.height) <= maxEdge;
    if (fitsUnchanged) {
      return PiImage(
        name: name,
        mimeType: sniffed,
        base64Data: base64Encode(bytes),
        width: decoded.width,
        height: decoded.height,
      );
    }

    for (final edge in _edgeLadder) {
      if (edge > maxEdge) continue;
      final resized = await _encodeWithinEdge(decoded, edge);
      if (resized.bytes.length > maxBytes) continue;
      return PiImage(
        name: name,
        mimeType: 'image/png',
        base64Data: base64Encode(resized.bytes),
        width: resized.width,
        height: resized.height,
      );
    }

    throw ImageAttachmentError(
      '"$name" is too large to send (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
      'Try a smaller crop.',
    );
  } finally {
    decoded.dispose();
  }
}
