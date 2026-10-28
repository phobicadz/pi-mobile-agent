import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

/// A backend whose session restore does not finish until the test says so, which
/// is the only way to see the state the app is supposed to show while it runs.
class _ControlledResumeService extends PiService {
  final Completer<List<Map<String, dynamic>>> _history =
      Completer<List<Map<String, dynamic>>>();

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => const Stream.empty();

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  bool get isConnected => true;

  /// There is no socket behind this service, and the real one no-ops while it is
  /// down. Match that rather than reaching for a channel that was never opened.
  @override
  Future<void> refreshState() async {}

  @override
  Future<List<PiSessionInfo>> listSessions() async => [
        PiSessionInfo(
          path: '/sessions/old.jsonl',
          id: 'old',
          cwd: '/home/adam/project',
          name: 'The one from earlier',
          preview: 'fix the build',
          messageCount: 2,
          modified: DateTime.now(),
        ),
      ];

  @override
  Future<List<Map<String, dynamic>>> resumeSession(String sessionPath) =>
      _history.future;

  void completeResume() {
    if (_history.isCompleted) return;
    _history.complete([
      {
        'id': 'h1',
        'role': 'user',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'content': [
          {'type': 'text', 'text': 'the prompt from the saved session'}
        ],
      },
      {
        'id': 'h2',
        'role': 'assistant',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'content': [
          {'type': 'text', 'text': 'the reply from the saved session'}
        ],
      },
    ]);
  }
}

void main() {
  /// A few frames rather than pumpAndSettle: the busy indicator is an
  /// indeterminate spinner, which never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(_ControlledResumeService, PiViewModel)> pumpHome(
      WidgetTester tester) async {
    final service = _ControlledResumeService();
    final viewModel = PiViewModel(piService: service);
    await tester.pumpWidget(
      ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await settle(tester);
    return (service, viewModel);
  }

  testWidgets('restoring a session shows a busy state over the chat',
      (tester) async {
    final (service, viewModel) = await pumpHome(tester);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.history));
    await settle(tester);
    expect(find.text('The one from earlier'), findsOneWidget);

    await tester.tap(find.byType(ListTile).first);
    await settle(tester);

    expect(viewModel.resumingSession, isTrue);
    expect(find.text('Restoring session…'), findsOneWidget,
        reason:
            'reading every saved session and handing the history back takes '
            'seconds, and with nothing on screen that looks like a frozen app');
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    service.completeResume();
    await settle(tester);

    expect(find.text('Restoring session…'), findsNothing,
        reason: 'the notice has to leave when the work does');
    expect(viewModel.resumingSession, isFalse);
    expect(find.text('the reply from the saved session'), findsOneWidget,
        reason: 'and the chat it was covering is the restored conversation');

    viewModel.dispose();
  });

  testWidgets('the history button is closed while a session is being restored',
      (tester) async {
    final (service, viewModel) = await pumpHome(tester);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.history));
    await settle(tester);
    await tester.tap(find.byType(ListTile).first);
    await settle(tester);

    final button = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.history));
    expect(button.onPressed, isNull,
        reason: 'a second resume started over the first would race the history '
            'being loaded into the live session');

    service.completeResume();
    await settle(tester);

    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.history))
            .onPressed,
        isNotNull);

    viewModel.dispose();
  });

  testWidgets('a failed restore clears the busy state instead of hanging',
      (tester) async {
    final service = _FailingResumeService();
    final viewModel = PiViewModel(piService: service);
    await tester.pumpWidget(
      ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await settle(tester);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.history));
    await settle(tester);
    await tester.tap(find.byType(ListTile).first);
    await settle(tester);

    expect(viewModel.resumingSession, isFalse,
        reason: 'the failure path has to release the busy state too, or the '
            'app stays "restoring" forever');
    expect(find.text('Restoring session…'), findsNothing);
    expect(viewModel.error, contains('Failed to resume session'));
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.history))
            .onPressed,
        isNotNull);

    viewModel.dispose();
  });
}

/// A restore that fails, to check the busy state is released on that path too.
class _FailingResumeService extends PiService {
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
  Future<List<PiSessionInfo>> listSessions() async => [
        PiSessionInfo(
          path: '/sessions/broken.jsonl',
          id: 'broken',
          cwd: '/home/adam/project',
          preview: 'broken',
          messageCount: 0,
          modified: DateTime.now(),
        ),
      ];

  @override
  Future<List<Map<String, dynamic>>> resumeSession(String sessionPath) async {
    throw Exception('session file could not be read');
  }
}
