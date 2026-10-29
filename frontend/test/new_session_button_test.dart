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
      // HomeScreen reads the appearance settings, so a test that builds it has
      // to supply them the way main.dart does.
      ChangeNotifierProvider<AppearanceController>(
        create: (_) => AppearanceController(),
        child: ChangeNotifierProvider<PiViewModel>.value(
          value: viewModel,
          child: const MaterialApp(home: HomeScreen()),
        ),
      ),
    );
    await settle(tester);

    await viewModel.submitPrompt('build something');
    await tester.pump();
    service.emit({'type': 'agent_end', 'messages': []});
    await settle(tester);

    return (viewModel, service);
  }

  testWidgets('the app bar opens a menu, and the menu carries new session',
      (tester) async {
    final (viewModel, _) = await pumpChat(tester);

    // The one control on the bar: the hamburger. Top left - the leftmost thing
    // on the screen, and level with the title.
    final menu = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.menu),
    );
    expect(menu, findsOneWidget, reason: 'the menu is operated from the bar');
    expect(tester.widget<IconButton>(
            find.ancestor(of: menu, matching: find.byType(IconButton)))
        .onPressed,
        isNotNull);

    final left = tester.getTopLeft(menu);
    final titleTop = tester.getTopLeft(find.text('Pi Agent')).dy;
    expect(left.dx, lessThan(60));
    expect(left.dy, closeTo(titleTop, 40));

    // Nothing else on the bar that does something.
    expect(
        tester
            .widgetList<IconButton>(find.descendant(
                of: find.byType(AppBar), matching: find.byType(IconButton)))
            .where((b) => b.onPressed != null)
            .length,
        1,
        reason: 'the controls are in the menu now, not crowded along the bar');

    await openAppMenu(tester);
    expect(find.text('New session'), findsOneWidget);
    expect(tester.widget<ListTile>(menuRow(Icons.add)).onTap, isNotNull);

    await tapMenuRow(tester, Icons.add);
    expect(tester.takeException(), isNull);

    viewModel.dispose();
  });

  testWidgets('tapping it starts a fresh chat in the same directory',
      (tester) async {
    final (viewModel, service) = await pumpChat(tester);

    expect(viewModel.messages, isNotEmpty);
    final directoryBefore = viewModel.workingDirectory;

    await openAppMenu(tester);
    await tapMenuRow(tester, Icons.add);
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
      // HomeScreen reads the appearance settings, so a test that builds it has
      // to supply them the way main.dart does.
      ChangeNotifierProvider<AppearanceController>(
        create: (_) => AppearanceController(),
        child: ChangeNotifierProvider<PiViewModel>.value(
          value: viewModel,
          child: const MaterialApp(home: HomeScreen()),
        ),
      ),
    );
    await settle(tester);

    // A run that no agent_end has closed: the chat is busy.
    await viewModel.submitPrompt('still working');
    await settle(tester);
    expect(viewModel.isLoading, isTrue);

    await openAppMenu(tester);
    expect(
        tester.widget<ListTile>(menuRow(Icons.add)).onTap,
        isNull,
        reason: 'starting over mid-run would throw away a reply that is still '
            'being written');

    await tester.tap(menuRow(Icons.add));
    await settle(tester);
    expect(service.newSessionCalls, isZero,
        reason: 'a closed control must not start a session');

    viewModel.dispose();
  });
}
