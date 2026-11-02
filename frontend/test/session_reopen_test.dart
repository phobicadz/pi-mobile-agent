import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

/// A backend that is already holding a conversation, and reports it through
/// `get_messages` the way the real one does.
///
/// This is the state a phone lands in when the app is closed completely and
/// opened again: the backend's Pi child process was never stopped, so the
/// reconnect joins a session that has been running the whole time - in its own
/// directory, with its own history and its own token totals. Nothing here is a
/// resumed session; it is the live one.
class _LiveSessionService extends PiService {
  final StreamController<PiState> _states = StreamController<PiState>.broadcast();

  /// What `get_messages` answers. Empty for the tests about a fresh session.
  List<Map<String, dynamic>> history = [];

  /// How many times the app asked, so a test can say it asked once.
  int historyRequests = 0;

  _LiveSessionService();

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
          'input': 40000,
          'output': 2000,
          'total': 42000
        },
        'contextUsage': {'tokens': 42000, 'contextWindow': 200000, 'percent': 21},
      });

  @override
  Future<List<Map<String, dynamic>>> loadCurrentHistory() async {
    historyRequests += 1;
    return history;
  }

  /// The frame the backend sends the moment a client connects.
  void pushState({bool processing = false}) {
    _states.add(PiState(
      isProcessing: processing,
      cwd: '/home/adam/project',
      cwdDisplay: '~/project',
      gitBranch: 'main',
    ));
  }
}

List<Map<String, dynamic>> _conversation() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return [
    {
      'id': 'live-1',
      'role': 'user',
      'timestamp': now,
      'content': [
        {'type': 'text', 'text': 'the prompt sent before the app was closed'}
      ],
    },
    {
      'id': 'live-2',
      'role': 'assistant',
      'timestamp': now,
      'content': [
        {'type': 'text', 'text': 'the reply that finished while it was closed'}
      ],
    },
  ];
}

void main() {
  /// A few frames rather than pumpAndSettle: the connecting screen spins, which
  /// never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(_LiveSessionService, PiViewModel)> pumpHome(
      WidgetTester tester, _LiveSessionService service) async {
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

  testWidgets('reopening the app shows the conversation it reconnected to',
      (tester) async {
    final service = _LiveSessionService()..history = _conversation();
    final (_, _) = await pumpHome(tester, service);

    expect(find.text('the reply that finished while it was closed'), findsNothing,
        reason: 'nothing has been said about the session yet');

    service.pushState();
    await settle(tester);

    expect(find.text('the prompt sent before the app was closed'), findsOneWidget);
    expect(find.text('the reply that finished while it was closed'), findsOneWidget,
        reason: 'the backend never stopped running just because the app did, so '
            'the chat has to show the session the socket actually rejoined - '
            'otherwise the bar carries a conversation the chat denies having');
  });

  testWidgets('the directory and the context belong to the session being shown',
      (tester) async {
    final service = _LiveSessionService()..history = _conversation();
    final (_, viewModel) = await pumpHome(tester, service);

    service.pushState();
    await settle(tester);

    expect(viewModel.workingDirectory, '/home/adam/project');
    expect(viewModel.messages.length, 2,
        reason: 'the percentage in the app bar is measured over these messages; '
            'showing it above an empty chat is the mismatch that made the '
            'number look like it came from somewhere else');
    expect(find.text('21%'), findsOneWidget);
  });

  testWidgets('a run in flight is not rebuilt from what has been persisted',
      (tester) async {
    final service = _LiveSessionService()..history = _conversation();
    await pumpHome(tester, service);

    service.pushState(processing: true);
    await settle(tester);

    expect(service.historyRequests, 0,
        reason: 'mid-run the chat is being built from the live event stream, and '
            'swapping in the messages saved so far would drop the reply arriving '
            'right now');
  });

  testWidgets('a fresh session is not searched for a conversation',
      (tester) async {
    final service = _LiveSessionService();
    final (_, viewModel) = await pumpHome(tester, service);

    service.pushState();
    await settle(tester);
    service.pushState();
    await settle(tester);

    expect(viewModel.messages, isEmpty);
    expect(service.historyRequests, 2,
        reason: 'asking is cheap and the answer being empty is a real answer - '
            'a new session genuinely has nothing, and the chat stays empty '
            'without being cleared to put nothing back in it');
  });
}
