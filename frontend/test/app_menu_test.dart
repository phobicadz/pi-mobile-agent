import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/directory_browser.dart';
import 'package:pi_mobile_agent/widgets/file_browser.dart';
import 'package:provider/provider.dart';

import 'support/app_menu.dart';

/// A connected backend that reports a working directory, which is what the menu
/// describes in its header.
class _MenuService extends PiService {
  final _states = StreamController<PiState>.broadcast();

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

  void reportDirectory(String cwd, String cwdDisplay) {
    _states.add(PiState(cwd: cwd, cwdDisplay: cwdDisplay));
  }
}

Future<(PiViewModel, _MenuService)> pumpHome(WidgetTester tester) async {
  final service = _MenuService();
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
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return (viewModel, service);
}

void main() {
  testWidgets('the menu carries every control the bar used to carry',
      (tester) async {
    final (viewModel, _) = await pumpHome(tester);

    await openAppMenu(tester);

    for (final label in const [
      'New session',
      'Working directory',
      'Resume a previous session',
      'Browse and view files',
      'Chat text size',
      'Switch to dark mode',
    ]) {
      expect(find.text(label), findsOneWidget,
          reason: 'the menu replaced the icons, so it has to say in words what '
              'each icon meant');
    }

    viewModel.dispose();
  });

  testWidgets('resuming a session sits above the directory a session runs in',
      (tester) async {
    final (viewModel, _) = await pumpHome(tester);

    await openAppMenu(tester);

    // Tree order, not screen position: a menu that scrolls still has an order.
    final titles = tester
        .widgetList<ListTile>(find.descendant(
            of: find.byType(Drawer), matching: find.byType(ListTile)))
        .map((tile) => (tile.title as Text).data ?? '')
        .toList();

    expect(titles.indexOf('Resume a previous session'),
        lessThan(titles.indexOf('Working directory')),
        reason: 'coming back to a conversation is the thing the menu is most '
            'often opened for, and the directory is set once and left alone');

    viewModel.dispose();
  });
  testWidgets('the bar carries the menu and the connection state, nothing else',
      (tester) async {
    final (viewModel, _) = await pumpHome(tester);

    for (final icon in const [
      Icons.add,
      Icons.history,
      Icons.description,
      Icons.folder_outlined,
      Icons.dark_mode,
      Icons.light_mode,
      Icons.text_decrease,
      Icons.text_increase,
    ]) {
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon)),
        findsNothing,
        reason: '$icon is in the menu now',
      );
    }

    expect(find.byIcon(Icons.menu), findsOneWidget);

    viewModel.dispose();
  });

  testWidgets('the menu states what the app is currently set to',
      (tester) async {
    final (viewModel, service) = await pumpHome(tester);
    service.reportDirectory('/home/adam/source/repos/pi-mobile-agent',
        '~/source/repos/pi-mobile-agent');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await openAppMenu(tester);

    expect(find.text('Connected'), findsOneWidget,
        reason: 'the dot in the bar is a colour with no words attached to it; '
            'the menu is where those words exist');
    expect(find.text('~/source/repos/pi-mobile-agent'), findsWidgets,
        reason:
            'which directory a new session would be started in is the thing '
            'a person is deciding when they open this menu');
    await scrollMenuIntoView(tester, find.textContaining('% of the size'));
    expect(find.textContaining('100% of the size the chat was designed at'),
        findsOneWidget,
        reason:
            'a size control that does not say the current size is a control '
            'with no idea what it is set to');

    viewModel.dispose();
  });

  testWidgets('a row opens what it says it opens, and gets out of the way',
      (tester) async {
    final (viewModel, _) = await pumpHome(tester);

    Future<void> closeSheet() async {
      Navigator.of(tester.element(find.byType(AppBar).first)).pop();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await openAppMenu(tester);
    await tapMenuRow(tester, Icons.description);

    expect(find.byType(FileBrowser), findsOneWidget);
    expect(find.byType(Drawer), findsNothing,
        reason: 'a menu left standing over the thing it just opened hides half '
            'of it on a phone');

    // The sheet owns the screen while it is up: the bar is behind its barrier,
    // so the menu has to be reached after it is put away.
    await closeSheet();

    await openAppMenu(tester);
    await tapMenuRow(tester, Icons.folder_outlined);
    expect(find.byType(DirectoryBrowser), findsOneWidget);

    viewModel.dispose();
  });
}
