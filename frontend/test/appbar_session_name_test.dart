import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

import 'support/app_menu.dart';

/// A backend that reports the conversation its Pi process is actually in, which
/// is the only thing that can say what the app bar should show next to the
/// directory.
class _NamedService extends PiService {
  final StreamController<PiState> _states = StreamController<PiState>.broadcast();

  static const livePath = '/home/adam/.pi/agent/sessions/--home-adam--/live.jsonl';

  String? sessionName;
  String cwd = '/home/adam/source/repos/pi-mobile-agent';

  /// What the app asked to rename the session to.
  final List<String?> renames = [];

  @override
  Stream<PiState> get stateUpdates => _states.stream;
  @override
  Stream<PiEvent> get events => const Stream.empty();
  @override
  bool get isConnected => true;
  @override
  Future<List<PiModel>> getAvailableModels() async => const [];
  @override
  Future<List<Map<String, dynamic>>> loadCurrentHistory() async => const [];

  @override
  Future<PiSessionStats> getSessionStats() async => PiSessionStats.fromJson({
        'tokens': {'input': 1000, 'output': 0, 'total': 1000},
        'contextUsage': {'tokens': 1000, 'contextWindow': 200000, 'percent': 1},
      });

  @override
  Future<void> refreshState() async => push();

  @override
  Future<List<PiSessionInfo>> listSessions() async => [
        PiSessionInfo(
          path: livePath,
          id: 'live',
          cwd: cwd,
          name: sessionName,
          preview: 'the first message',
          messageCount: 3,
          modified: DateTime.now(),
        ),
      ];

  @override
  Future<void> renameSession(String sessionPath, String? name) async {
    renames.add(name);
    sessionName = name;
    // The live Pi writes the name into the session it is holding, and the state
    // it reports afterwards is what the bar shows. Simulating the write without
    // the report is how a test passes over a bar that never updates.
    push();
  }

  @override
  Future<void> newSession() async {
    // Pi starts a fresh conversation with no name on it, and the backend asks
    // for the state again right after - which is the report that has to arrive.
    sessionName = null;
    push();
  }

  void push() {
    _states.add(PiState(
      cwd: cwd,
      cwdDisplay: '~/${cwd.split('/').skip(3).join('/')}',
      sessionName: sessionName,
    ));
  }
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(_NamedService, PiViewModel)> pumpHome(
    WidgetTester tester, {
    String? sessionName,
    Size width = const Size(390, 844),
  }) async {
    tester.view.physicalSize = width;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _NamedService()..sessionName = sessionName;
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
    service.push();
    await settle(tester);
    return (service, viewModel);
  }

  Finder folderName() => find.text('pi-mobile-agent');
  Finder sessionName() => find.text('[garden siren diagnosis]');

  testWidgets('the bar names the conversation next to the directory',
      (tester) async {
    final (_, viewModel) =
        await pumpHome(tester, sessionName: 'garden siren diagnosis');

    expect(sessionName(), findsOneWidget,
        reason: 'which directory and which conversation in it are the two halves '
            'of "where am I", and only the directory was ever on screen');

    final folder = tester.getRect(folderName());
    final name = tester.getRect(sessionName());
    expect(name.left, greaterThan(folder.right),
        reason: 'in brackets after the folder name, which is the order the '
            'question is asked in');
    expect(name.left, lessThan(name.right));

    viewModel.dispose();
  });

  testWidgets('an unnamed session shows nothing rather than a placeholder',
      (tester) async {
    final (_, viewModel) = await pumpHome(tester);

    expect(folderName(), findsOneWidget);
    expect(find.text('[]'), findsNothing);
    expect(find.textContaining('Session:'), findsNothing,
        reason: 'a bar that says "[]" for every chat nobody named is a bar with '
            'a decoration on it');

    viewModel.dispose();
  });

  testWidgets('a long name gives way rather than pushing the directory out',
      (tester) async {
    final (_, viewModel) = await pumpHome(
      tester,
      sessionName: 'refactor the mobile agent title bar layout and context meter',
    );

    expect(folderName(), findsOneWidget,
        reason: 'the directory is the primary half of the bar; a session name '
            'that squeezed it out would be labelling the wrong thing');

    final bar = tester.getRect(find.byType(AppBar));
    final name = tester.getRect(
      find.textContaining('[refactor the mobile agent'),
    );
    expect(name.right, lessThanOrEqualTo(bar.right));
    expect(name.width, lessThan(bar.width * 0.6),
        reason: 'it gets the smaller share of the flex, so a long one ellipsizes '
            'its own half instead of the path');

    viewModel.dispose();
  });

  testWidgets('renaming the live session renames the bar', (tester) async {
    final (service, viewModel) =
        await pumpHome(tester, sessionName: 'garden siren diagnosis');

    await openAppMenu(tester);
    await tapMenuRow(tester, Icons.history);
    await settle(tester);

    final row = find.ancestor(
      of: find.text('garden siren diagnosis'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
    );
    await settle(tester);

    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'title bar layout work',
    );
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(service.renames, ['title bar layout work']);
    expect(find.text('[title bar layout work]'), findsOneWidget,
        reason: 'the bar shows the name Pi reports for the session it is in, so '
            'renaming where you are has to show up where you are');
    expect(find.text('[garden siren diagnosis]'), findsNothing);

    viewModel.dispose();
  });

  testWidgets('a new session clears the name from the bar', (tester) async {
    final (_, viewModel) =
        await pumpHome(tester, sessionName: 'garden siren diagnosis');

    await viewModel.startNewSession();
    await settle(tester);

    expect(find.text('[garden siren diagnosis]'), findsNothing,
        reason: 'a bar still naming the conversation that was just left behind '
            'describes a session it is no longer in');

    viewModel.dispose();
  });
}
