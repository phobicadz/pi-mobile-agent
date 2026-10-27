import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

/// Answers prompts, reports a live connection (HomeScreen shows nothing but a
/// spinner otherwise), and records the new_session command the add button sends.
class FakeNewSessionService extends PiService {
  final _events = StreamController<PiEvent>.broadcast();
  int newSessionCalls = 0;

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => _events.stream;

  @override
  bool get isConnected => true;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<void> sendPrompt(String message) async {}

  @override
  Future<void> newSession() async {
    newSessionCalls++;
    // Pi settles the run it was in before handing over the fresh session, so the
    // chat is not left thinking it is still busy.
    emit({'type': 'agent_end', 'messages': []});
  }

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// HomeScreen with one finished exchange on screen.
  Future<(PiViewModel, FakeNewSessionService)> pumpChat(
      WidgetTester tester) async {
    final service = FakeNewSessionService();
    final viewModel = PiViewModel(piService: service);
    await tester.pumpWidget(
      ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await settle(tester);

    await viewModel.submitPrompt('build something');
    await tester.pump();
    service.emit({'type': 'agent_end', 'messages': []});
    await settle(tester);

    return (viewModel, service);
  }

  testWidgets('the app bar carries a new-session button at the top left',
      (tester) async {
    final (viewModel, _) = await pumpChat(tester);

    final add = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.add),
    );
    expect(add, findsOneWidget, reason: 'the button lives in the app bar');

    final button = tester.widget<IconButton>(
      find.ancestor(of: add, matching: find.byType(IconButton)),
    );
    expect(button.onPressed, isNotNull);

    // Top left: the leftmost thing on the screen, and level with the title.
    final left = tester.getTopLeft(add);
    final titleTop = tester.getTopLeft(find.text('Pi Agent')).dy;
    expect(left.dx, lessThan(60));
    expect(left.dy, closeTo(titleTop, 40));

    await tester.tap(add);
    await settle(tester);
    expect(tester.takeException(), isNull);

    viewModel.dispose();
  });

  testWidgets('tapping it starts a fresh chat in the same directory',
      (tester) async {
    final (viewModel, service) = await pumpChat(tester);

    expect(viewModel.messages, isNotEmpty);
    final directoryBefore = viewModel.workingDirectory;

    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);

    expect(service.newSessionCalls, 1);
    expect(viewModel.messages, isEmpty, reason: 'a new chat starts empty');
    expect(viewModel.workingDirectory, directoryBefore,
        reason: 'the new session belongs to the directory being worked in');
    expect(viewModel.error, isNull);

    viewModel.dispose();
  });

  testWidgets('the button is disabled while a run is in flight',
      (tester) async {
    final service = FakeNewSessionService();
    final viewModel = PiViewModel(piService: service);
    await tester.pumpWidget(
      ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await settle(tester);

    // A run that no agent_end has closed: the chat is busy.
    await viewModel.submitPrompt('still working');
    await settle(tester);
    expect(viewModel.isLoading, isTrue);

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    expect(service.newSessionCalls, isZero,
        reason: 'a disabled button must not start a session');

    viewModel.dispose();
  });
}
