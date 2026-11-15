import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/file_viewer.dart';
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

/// Real PNG bytes, made before any test runs: `toImage` completes on the real
/// event loop, which `testWidgets` does not have.
late String pngBase64;

/// PiService stub that answers readFile with canned file contents - exactly what
/// the backend's `read_file` sends back for each kind of file.
class FakeFileService extends PiService {
  final Map<String, FileContent> files;
  final _events = StreamController<PiEvent>.broadcast();

  FakeFileService({required this.files});

  @override
  Stream<PiEvent> get events => _events.stream;

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Future<FileContent> readFile(String path) async {
    final file = files[path];
    if (file == null) throw Exception('File not found: $path');
    return file;
  }
}

/// What the backend answers for an image file: the bytes as base64, the MIME
/// type it read off them, and no text content to draw.
FileContent _imageFile({String? base64Data, String mimeType = 'image/png'}) =>
    FileContent(
      content: '',
      size: 4096,
      isText: false,
      encoding: 'base64',
      mimeType: mimeType,
      base64Data: base64Data ?? pngBase64,
    );

/// A file that is not an image and not text either - a compiled object, say.
/// The viewer has always had an answer for this one and it is not a picture.
FileContent _otherBinary() => FileContent(
      content: String.fromCharCodes([0, 1, 2, 3, 200, 201]),
      size: 6,
      isText: false,
      encoding: 'binary',
    );

const _sourceFile = 'report/genome.png';

/// Opens the viewer for [path] with [content], the way the file browser does.
Future<void> _openViewer(
  WidgetTester tester, {
  required String path,
  required FileContent content,
}) async {
  final service = FakeFileService(files: {path: content});
  final viewModel = PiViewModel(piService: service);

  await tester.pumpWidget(
    ChangeNotifierProvider<PiViewModel>.value(
      value: viewModel,
      child: ChangeNotifierProvider<AppearanceController>.value(
        value: AppearanceController(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => FileViewer(
                    filePath: path,
                    fileName: path.split('/').last,
                  ),
                ),
                child: const Text('open file'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open file'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() async {
    pngBase64 = base64Encode(await pngOf(40, 40));
  });

  test('an image file is read as base64 and not as text', () {
    // The shape the backend's `read_file` answers with. `content` is empty on
    // purpose: a 2 MB photo carried as latin1 text as well is a 2 MB string
    // nobody renders.
    final file = _imageFile();
    expect(file.isImage, isTrue);
    expect(file.content, isEmpty);
    expect(file.imageFormatLabel, 'PNG');
    expect(_otherBinary().isImage, isFalse);
    expect(_otherBinary().imageFormatLabel, isNull);
  });

  testWidgets('a picture the agent made is drawn', (tester) async {
    await _openViewer(tester, path: _sourceFile, content: _imageFile());

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget,
        reason: 'a picture scaled to fit a phone is a picture you cannot read. '
            'The zoom is how the rest of it is seen');
    expect(find.textContaining('Pinch or scroll to zoom'), findsOneWidget);
  });

  testWidgets('the header names what it is instead of calling it binary',
      (tester) async {
    await _openViewer(tester, path: _sourceFile, content: _imageFile());

    expect(find.textContaining('PNG image'), findsOneWidget);
    expect(find.textContaining('binary'), findsNothing,
        reason: '"binary" is the app saying it has nothing to draw, and this '
            'one it can draw');
    expect(find.textContaining('lines'), findsNothing,
        reason: 'there are no lines in a picture. A line count for one is a '
            'number for a thing that is not there');
  });

  testWidgets('the controls a picture does not have are not offered',
      (tester) async {
    await _openViewer(tester, path: _sourceFile, content: _imageFile());

    expect(find.textContaining('Tap a line number'), findsNothing,
        reason: 'a line reference is a reference into text');
    expect(find.textContaining('% text size'), findsNothing);
    expect(find.byIcon(Icons.copy), findsNothing,
        reason: 'there is no text of the file to copy');
  });

  testWidgets('a file that is not an image is left exactly as it was',
      (tester) async {
    await _openViewer(
        tester, path: 'report/blob.bin', content: _otherBinary());

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('binary'), findsOneWidget);
    expect(find.textContaining('Tap a line number'), findsOneWidget);
  });

  testWidgets('a picture this browser cannot draw says so', (tester) async {
    await _openViewer(
      tester,
      path: _sourceFile,
      content: _imageFile(base64Data: 'not base64 at all !!!'),
    );

    expect(find.textContaining('could not be drawn'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
