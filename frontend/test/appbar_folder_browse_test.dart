import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/file_browser.dart';
import 'package:provider/provider.dart';

/// A backend with a directory to browse, so the sheet the folder opens has
/// something real in it.
class _BrowseService extends PiService {
  final StreamController<PiState> _states = StreamController<PiState>.broadcast();

  String cwd = '/home/adam/project';

  @override
  Stream<PiState> get stateUpdates => _states.stream;

  @override
  Stream<PiEvent> get events => const Stream.empty();

  @override
  bool get isConnected => true;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<void> refreshState() async {}

  @override
  Future<PiSessionStats> getSessionStats() async => PiSessionStats.fromJson({
        'tokens': {
          'input': 0,
          'output': 0,
          'total': 0
        },
      });

  @override
  Future<List<Map<String, dynamic>>> loadCurrentHistory() async => const [];

  @override
  Future<FileListing> listFiles({String? path}) async {
    final target = path ?? cwd;
    return FileListing(
      path: target,
      parent: '/home/adam',
      current: target,
      cwdDisplay: '~/project',
      roots: [
        DirEntry(name: 'adam', path: '/home/adam', isDirectory: true),
      ],
      entries: [
        DirEntry(name: 'src', path: '$target/src', isDirectory: true),
        DirEntry(
            name: 'index.ts',
            path: '$target/index.ts',
            isDirectory: false,
            size: 120),
      ],
      recent: const ['/home/adam/other'],
    );
  }

  void pushState() {
    _states.add(PiState(
      cwd: cwd,
      cwdDisplay: '~/project',
      gitBranch: 'main',
    ));
  }
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpHome(WidgetTester tester, _BrowseService service) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final viewModel = PiViewModel(piService: service);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppearanceController>(
        create: (_) => AppearanceController(),
        child: ChangeNotifierProvider<PiViewModel>.value(
          value: viewModel,
          child: const MaterialApp(home: HomeScreen()),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('the folder in the bar opens the file browser', (tester) async {
    final service = _BrowseService();
    await pumpHome(tester, service);
    service.pushState();
    await settle(tester);

    expect(find.byType(FileBrowser), findsNothing);

    await tester.tap(find.text('project'));
    await settle(tester);

    expect(find.byType(FileBrowser), findsOneWidget,
        reason: 'the bar already says which directory this is, so it should be '
            'the thing that changes it rather than a label that sends you to a '
            'menu to change it');
    expect(find.text('src'), findsOneWidget,
        reason: 'and it has to open on the directory being shown, not somewhere else');
  });

  testWidgets('the folder in the bar is a control, not just text',
      (tester) async {
    final service = _BrowseService();
    await pumpHome(tester, service);
    service.pushState();
    await settle(tester);

    // The bar holds other InkWells - the menu button among them - so this is
    // found from the folder it is supposed to wrap.
    final inkWell = tester.widget<InkWell>(
      find.ancestor(
        of: find.byIcon(Icons.folder_open),
        matching: find.byType(InkWell),
      ),
    );
    expect(inkWell.onTap, isNotNull,
        reason: 'a tappable-looking name that does nothing is worse than plain '
            'text, because it is pressed and nothing happens');
  });

  testWidgets('the full path is still what the folder explains', (tester) async {
    final service = _BrowseService();
    await pumpHome(tester, service);
    service.pushState();
    await settle(tester);

    expect(find.byTooltip('/home/adam/project'), findsOneWidget,
        reason: 'the bar shortens the path because it has no room for it, so the '
            'tooltip is the only place the real directory is written out');
  });
}
