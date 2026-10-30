import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/file_browser.dart';
import 'package:pi_mobile_agent/widgets/file_viewer.dart';
import 'package:provider/provider.dart';

import 'support/app_menu.dart';

/// A backend that can list a directory and read the one file in it.
class _FileService extends PiService {
  final _states = StreamController<PiState>.broadcast();

  static const filePath = '/srv/app.ts';
  static const fileContent = '''alpha
bravo
charlie
delta
echo
''';

  @override
  Stream<PiState> get stateUpdates => _states.stream;

  @override
  Stream<PiEvent> get events => const Stream.empty();

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  bool get isConnected => true;

  @override
  Future<void> refreshState() async {}

  @override
  Future<FileListing> listFiles({String? path}) async => FileListing(
        path: path ?? '/srv',
        roots: const [],
        entries: [
          DirEntry(
              name: 'app.ts', path: filePath, isDirectory: false, size: 34),
        ],
        recent: const [],
      );

  @override
  Future<FileContent> readFile(String path) async => FileContent(
        content: fileContent,
        size: fileContent.length,
        isText: true,
        encoding: 'utf-8',
      );
}

Future<PiViewModel> pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final viewModel = PiViewModel(piService: _FileService());
  await tester.pumpWidget(
    ChangeNotifierProvider<AppearanceController>(
      create: (_) => AppearanceController(),
      child: ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return viewModel;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Type a half-finished sentence into the composer, the way it is when a file is
/// opened: the reference is wanted mid-thought, not as a fresh message.
Future<void> startTyping(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'explain what ');
  await settle(tester);
}

/// Open the browser sheet and the viewer for the file in it.
Future<void> openFile(WidgetTester tester) async {
  await openAppMenu(tester);
  await tapMenuRow(tester, Icons.folder_open);
  expect(find.byType(FileBrowser), findsOneWidget);

  await tester.tap(find.text('app.ts'));
  await settle(tester);
  expect(find.byType(FileViewer), findsOneWidget);
}

void main() {
  testWidgets('selecting lines offers to put them in the prompt',
      (tester) async {
    final viewModel = await pumpHome(tester);
    await startTyping(tester);
    await openFile(tester);

    expect(find.text('Put lines 2–4 in the prompt'), findsNothing,
        reason: 'nothing is selected yet, so there is no range to offer');

    await tester.tap(find.text('2'));
    await settle(tester);
    expect(find.text('Put line 2 in the prompt'), findsOneWidget);

    await tester.tap(find.text('4'));
    await settle(tester);
    expect(find.text('Put lines 2–4 in the prompt'), findsOneWidget);

    viewModel.dispose();
  });

  testWidgets(
      'the button puts the reference where the sentence was being '
      'written and gets out of the way', (tester) async {
    final viewModel = await pumpHome(tester);
    await startTyping(tester);
    await openFile(tester);

    await tester.tap(find.text('2'));
    await settle(tester);
    await tester.tap(find.text('4'));
    await settle(tester);

    await tester.tap(find.text('Put lines 2–4 in the prompt'));
    await settle(tester);

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'explain what /srv/app.ts:2-4',
        reason: 'the reference belongs in the sentence the user was already '
            'writing; a clipboard they then have to paste from is the same '
            'result reached in three steps');
    expect(viewModel.userInput, 'explain what /srv/app.ts:2-4',
        reason:
            'the draft the view model keeps has to match what is on screen, '
            'or switching session throws away typing the user can still see');
    expect(field.controller!.selection.baseOffset, 28,
        reason: 'the caret sits after the reference so the sentence continues');

    expect(find.byType(FileViewer), findsNothing);
    expect(find.byType(FileBrowser), findsNothing,
        reason: 'on a phone the prompt field is behind these, so a reference '
            'inserted into a field the user cannot see is one they have to '
            'trust rather than check');

    viewModel.dispose();
  });

  testWidgets('a single line is referenced as one line', (tester) async {
    final viewModel = await pumpHome(tester);
    await startTyping(tester);
    await openFile(tester);

    await tester.tap(find.text('3'));
    await settle(tester);
    await tester.tap(find.text('Put line 3 in the prompt'));
    await settle(tester);

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'explain what /srv/app.ts:3');

    viewModel.dispose();
  });
}
