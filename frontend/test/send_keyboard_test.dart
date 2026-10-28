import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

/// Replays canned backend frames; the send succeeds so the turn behaves like a
/// normal one rather than failing on a missing socket.
class FakeSendService extends PiService {
  final StreamController<PiEvent> _events =
      StreamController<PiEvent>.broadcast();

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => _events.stream;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<void> sendPrompt(String message) async {}

  /// HomeScreen keeps a full-screen connecting spinner until the socket is up, so
  /// the composer only exists once the service reports a connection.
  @override
  bool get isConnected => true;

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));
}

/// Whether the prompt field currently holds focus. On a phone that *is* the
/// on-screen keyboard, which is the thing the test is really about.
bool fieldHasFocus(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  /// A few frames rather than pumpAndSettle: the app keeps an indeterminate
  /// spinner somewhere, which never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(FakeSendService, PiViewModel)> pumpHome(WidgetTester tester) async {
    final service = FakeSendService();
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
    return (service, viewModel);
  }

  /// Focus the field, type into it, and press Return on the keyboard.
  Future<void> typeAndPressReturn(WidgetTester tester) async {
    await tester.tap(find.byType(TextField));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'a prompt sent with return');
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
  }

  testWidgets(
      'on a phone, Return releases the field the way the send button does',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final (_, viewModel) = await pumpHome(tester);

    await tester.tap(find.byType(TextField));
    await settle(tester);
    expect(fieldHasFocus(tester), isTrue,
        reason: 'the fixture has to be holding the keyboard to lose it');

    await typeAndPressReturn(tester);

    // The prompt is stored and the turn is running: Return still sends, and the
    // only thing that changed is where the keyboard went.
    expect(viewModel.messages.length, 1);
    expect(viewModel.isLoading, isTrue);
    expect(fieldHasFocus(tester), isFalse,
        reason: 'on a touch platform focus is the on-screen keyboard, and it '
            'stayed over the reply the user had just sent');

    debugDefaultTargetPlatformOverride = null;
    viewModel.dispose();
  });

  testWidgets(
      'the keyboard is not brought back when the run finishes on a phone',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final (service, viewModel) = await pumpHome(tester);

    await typeAndPressReturn(tester);
    expect(fieldHasFocus(tester), isFalse);
    expect(viewModel.isLoading, isTrue, reason: 'the turn is still running');

    // The turn ending is exactly when the user came back to read the reply. If
    // the app asked for focus there, the keyboard would land on top of it.
    service.emit({'type': 'agent_end', 'messages': []});
    await settle(tester);
    expect(viewModel.isLoading, isFalse);

    expect(fieldHasFocus(tester), isFalse,
        reason: 'the run ending must not reopen the keyboard over the reply');

    debugDefaultTargetPlatformOverride = null;
    viewModel.dispose();
  });

  testWidgets('on a desktop the field keeps focus after Return',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final (_, viewModel) = await pumpHome(tester);

    await typeAndPressReturn(tester);

    expect(viewModel.messages.length, 1);
    expect(viewModel.isLoading, isTrue);
    expect(fieldHasFocus(tester), isTrue,
        reason: 'there is no keyboard to hide here, and holding focus is what '
            'lets the next prompt be typed while the agent works');

    debugDefaultTargetPlatformOverride = null;
    viewModel.dispose();
  });
}
