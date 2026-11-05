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

/// A backend that keeps a session list the rename calls actually change, so a
/// test can tell "the name was sent" from "the name was painted over locally".
class _RenameService extends PiService {
  final List<PiSessionInfo> sessions = [
    PiSessionInfo(
      path: '/sessions/named.jsonl',
      id: 'named',
      cwd: '/home/adam/project',
      name: 'The one from earlier',
      preview: 'fix the build',
      messageCount: 4,
      modified: DateTime.now(),
    ),
    PiSessionInfo(
      path: '/sessions/unnamed.jsonl',
      id: 'unnamed',
      cwd: '/home/adam/project',
      preview: 'why is the garden siren going off',
      messageCount: 2,
      modified: DateTime.now(),
    ),
  ];

  /// Every rename the app asked for, in order.
  final List<(String, String?)> renames = [];

  /// What the model answers. A test can make this throw instead.
  String suggestedTitle = 'garden siren diagnosis';
  bool failSuggestion = false;

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => const Stream.empty();

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  bool get isConnected => true;

  @override
  Future<void> refreshState() async {}

  @override
  Future<List<PiSessionInfo>> listSessions() async => List.of(sessions);

  @override
  Future<void> renameSession(String sessionPath, String? name) async {
    renames.add((sessionPath, name));
    final index = sessions.indexWhere((s) => s.path == sessionPath);
    if (index == -1) throw Exception('no such session: $sessionPath');
    sessions[index] = PiSessionInfo(
      path: sessions[index].path,
      id: sessions[index].id,
      cwd: sessions[index].cwd,
      name: name,
      preview: sessions[index].preview,
      messageCount: sessions[index].messageCount,
      modified: sessions[index].modified,
    );
  }

  @override
  Future<String> suggestSessionTitle(String sessionPath) async {
    if (failSuggestion) throw Exception('The model took too long');
    return suggestedTitle;
  }
}

void main() {
  /// A few frames rather than pumpAndSettle: the sheet and the dialog both
  /// animate, and the suggestion button can hold a spinner that never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(_RenameService, PiViewModel)> pumpHome(WidgetTester tester) async {
    final service = _RenameService();
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
    return (service, viewModel);
  }

  /// Open the session picker and return the rename button of the row whose title
  /// contains [ofTitle].
  Future<void> openRenameFor(WidgetTester tester, String ofTitle) async {
    await openSessionPicker(tester);
    await settle(tester);

    final row = find.ancestor(
      of: find.text(ofTitle),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
    );
    await settle(tester);
  }

  Finder nameField() =>
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));

  testWidgets('every session in the list can be renamed', (tester) async {
    final (_, viewModel) = await pumpHome(tester);

    await openSessionPicker(tester);
    await settle(tester);

    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2),
        reason: 'a name is how a session is found again, so the control belongs '
            'on the list that is searched by name, not only inside a chat');

    viewModel.dispose();
  });

  testWidgets('typing a name and saving it renames that session',
      (tester) async {
    final (service, viewModel) = await pumpHome(tester);

    await openRenameFor(tester, 'why is the garden siren going off');
    expect(find.text('Name this session'), findsOneWidget,
        reason: 'an unnamed session is not being renamed, it is being named');

    await tester.enterText(nameField(), 'garden siren');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(service.renames, [( '/sessions/unnamed.jsonl', 'garden siren')]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('garden siren'), findsOneWidget,
        reason: 'the list the person is looking at has to show the name they '
            'just gave, not the one it had when the sheet opened');

    viewModel.dispose();
  });

  testWidgets('a suggested name goes into the field, not onto the session',
      (tester) async {
    final (service, viewModel) = await pumpHome(tester);

    await openRenameFor(tester, 'why is the garden siren going off');
    await tester.tap(find.text('Suggest a name'));
    await settle(tester);

    expect(service.renames, isEmpty,
        reason: 'what a model guessed about a conversation is worth seeing '
            'before it becomes that conversation\'s label');
    expect(tester.widget<TextField>(nameField()).controller!.text,
        'garden siren diagnosis',
        reason: 'so it arrives where it can be read and changed');

    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(service.renames, [('/sessions/unnamed.jsonl', 'garden siren diagnosis')]);

    viewModel.dispose();
  });

  testWidgets('a named session can be unnamed again', (tester) async {
    final (service, viewModel) = await pumpHome(tester);

    await openRenameFor(tester, 'The one from earlier');
    expect(find.text('Name this session'), findsNothing,
        reason: 'this one already has a name, and the dialog says which it is');
    expect(find.text('Rename “The one from earlier”'), findsOneWidget);

    await tester.tap(find.text('Clear name'));
    await settle(tester);

    expect(service.renames, [('/sessions/named.jsonl', null)],
        reason: 'clearing is sending no name, which is what Pi\'s own /name does '
            'with an empty one');
    expect(find.text('fix the build'), findsOneWidget,
        reason: 'an unnamed session falls back to its first message');

    viewModel.dispose();
  });

  testWidgets('a suggestion that fails says so and keeps the name already typed',
      (tester) async {
    final (service, viewModel) = await pumpHome(tester);
    service.failSuggestion = true;

    await openRenameFor(tester, 'The one from earlier');
    await tester.enterText(nameField(), 'keep this one');
    await tester.tap(find.text('Suggest a name'));
    await settle(tester);

    expect(find.textContaining('The model took too long'), findsOneWidget,
        reason: 'a button that stops working and says nothing looks like a tap '
            'that was ignored');
    expect(tester.widget<TextField>(nameField()).controller!.text,
        'keep this one',
        reason: 'a failed suggestion must not empty the field it failed into');
    expect(service.renames, isEmpty);

    viewModel.dispose();
  });
}
