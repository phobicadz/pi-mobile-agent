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

/// A backend with two saved sessions, one of which is the conversation its Pi
/// process is actually in - the distinction the picker has to get right.
class _DeletableService extends PiService {
  final StreamController<PiState> _states = StreamController<PiState>.broadcast();

  static const livePath = '/sessions/live.jsonl';
  static const otherPath = '/sessions/finished.jsonl';

  final List<PiSessionInfo> sessions = [
    PiSessionInfo(
      path: otherPath,
      id: 'finished',
      cwd: '/home/adam/project',
      name: 'the one that finished',
      preview: 'fix the build',
      messageCount: 6,
      modified: DateTime.now(),
    ),
    PiSessionInfo(
      path: livePath,
      id: 'live',
      cwd: '/home/adam/project',
      name: 'the one being had',
      preview: 'add delete support',
      messageCount: 3,
      modified: DateTime.now(),
    ),
  ];

  final List<String> deleted = [];
  bool failDelete = false;

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
  Future<List<Map<String, dynamic>>> loadCurrentHistory() async => const [];

  @override
  Future<PiSessionStats> getSessionStats() async => PiSessionStats.fromJson({
        'tokens': {'input': 1000, 'output': 0, 'total': 1000},
        'contextUsage': {'tokens': 1000, 'contextWindow': 200000, 'percent': 1},
      });

  @override
  Future<List<PiSessionInfo>> listSessions() async => List.of(sessions);

  @override
  Future<void> deleteSession(String sessionPath) async {
    if (failDelete) throw Exception('no such file: $sessionPath');
    deleted.add(sessionPath);
    sessions.removeWhere((s) => s.path == sessionPath);
  }

  void push() {
    _states.add(PiState(
      cwd: '/home/adam/project',
      cwdDisplay: '~/project',
      sessionName: 'the one being had',
      sessionFile: livePath,
    ));
  }
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(_DeletableService, PiViewModel)> pumpHome(WidgetTester tester) async {
    final service = _DeletableService();
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
    // The state is what says which session is live, so a picker opened without it
    // would be a picker with no way to know.
    service.push();
    await settle(tester);

    // This backend names the live session, so the centre of the bar shows the
    // name, and that is what opens the picker.
    await openSessionPicker(tester, sessionName: 'the one being had');
    await settle(tester);
    return (service, viewModel);
  }

  /// The delete button of the row titled [title].
  ///
  /// The button, not its icon: the icon is what is on screen but the thing being
  /// switched off is the button, and a finder for the first cannot be read as one
  /// for the second.
  Finder deleteFor(WidgetTester tester, String title) => find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
        matching: find.byIcon(Icons.delete_outline),
      );

  Finder deleteButtonFor(WidgetTester tester, String title) =>
      find.ancestor(of: deleteFor(tester, title), matching: find.byType(IconButton));

  /// A row in the picker sheet, by title. The app bar shows the live session's
  /// name too, so "the row called X" has to be asked for inside the sheet.
  Finder sheetRow(WidgetTester tester, String title) => find.descendant(
      of: find.byType(BottomSheet), matching: find.text(title));

  Future<void> openDeleteDialog(WidgetTester tester, String title) async {
    await tester.tap(deleteFor(tester, title));
    await settle(tester);
  }

  testWidgets('a saved session can be deleted, and the live one cannot',
      (tester) async {
    final (_, viewModel) = await pumpHome(tester);

    expect(deleteFor(tester, 'the one that finished'), findsOneWidget);
    expect(deleteFor(tester, 'the one being had'), findsOneWidget);

    expect(
        tester.widget<IconButton>(deleteButtonFor(tester, 'the one being had'))
            .onPressed,
        isNull,
        reason: 'its file is open and still being written to, so the row says so '
            'instead of the backend throwing at it');

    viewModel.dispose();
  });

  testWidgets('deleting asks first, and keeping it keeps it', (tester) async {
    final (service, viewModel) = await pumpHome(tester);

    await openDeleteDialog(tester, 'the one that finished');
    expect(find.text('Delete this session?'), findsOneWidget,
        reason: 'this removes a conversation, not a listing of one');
    expect(find.textContaining('6 messages in /home/adam/project'), findsOneWidget,
        reason: 'the thing about to be thrown away is worth naming before the '
            'button is pressed');

    await tester.tap(find.text('Keep it'));
    await settle(tester);

    expect(service.deleted, isEmpty);
    expect(sheetRow(tester, 'the one that finished'), findsOneWidget);

    viewModel.dispose();
  });

  testWidgets('confirming deletes it and it leaves the list', (tester) async {
    final (service, viewModel) = await pumpHome(tester);

    await openDeleteDialog(tester, 'the one that finished');
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(service.deleted, [_DeletableService.otherPath]);
    expect(sheetRow(tester, 'the one that finished'), findsNothing,
        reason: 'the list the person is looking at is the list on disk, not one '
            'with the row painted out locally');
    expect(sheetRow(tester, 'the one being had'), findsOneWidget,
        reason: 'and only that one went');

    viewModel.dispose();
  });

  testWidgets('a delete that fails leaves the session where it was',
      (tester) async {
    final (service, viewModel) = await pumpHome(tester);
    service.failDelete = true;

    await openDeleteDialog(tester, 'the one that finished');
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(sheetRow(tester, 'the one that finished'), findsOneWidget,
        reason: 'a row that vanished on a failed delete is a session the person '
            'can no longer reach and cannot get back');
    expect(viewModel.error, contains('no such file'));

    viewModel.dispose();
  });
}
