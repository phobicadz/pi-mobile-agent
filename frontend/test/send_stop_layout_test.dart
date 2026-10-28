import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

/// A service whose send succeeds but whose run never ends: no `agent_end` and no
/// state frame saying the agent stopped working, which is what leaves a run in
/// flight and the stop button on screen.
class RunningService extends PiService {
  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => const Stream.empty();

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<void> sendPrompt(String message) async {}

  @override
  bool get isConnected => true;
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(RunningService, PiViewModel)> pumpHome(WidgetTester tester) async {
    final service = RunningService();
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

  Rect sendButton(WidgetTester tester) =>
      tester.getRect(find.byIcon(Icons.send));
  Rect? stopButton(WidgetTester tester) {
    final found = find.byIcon(Icons.stop);
    return found.evaluate().isEmpty ? null : tester.getRect(found);
  }

  Future<void> startRun(WidgetTester tester, PiViewModel viewModel) async {
    viewModel.setUserInput('a run that is still going');
    await viewModel.submitPrompt();
    await settle(tester);
  }

  testWidgets('stop sits beside send instead of below it', (tester) async {
    final (_, viewModel) = await pumpHome(tester);
    await startRun(tester, viewModel);

    final stop = stopButton(tester);
    if (stop == null) {
      fail('a run in flight must offer a way to stop it');
    }
    final send = sendButton(tester);

    expect(stop.right, lessThanOrEqualTo(send.left + 1),
        reason: 'stop has to be to the left of send, not under it');
    expect((stop.center.dy - send.center.dy).abs(), lessThan(1.0),
        reason: 'the two are one control group, so they belong on one line');

    viewModel.dispose();
  });

  testWidgets('send does not move when stop appears', (tester) async {
    final (_, viewModel) = await pumpHome(tester);

    final before = sendButton(tester);
    await startRun(tester, viewModel);
    final during = sendButton(tester);

    expect(during.center.dx, closeTo(before.center.dx, 1),
        reason: 'the button pressed most often must not shift when the other '
            'one appears beside it');
    expect(during.top, closeTo(before.top, 1));

    viewModel.dispose();
  });

  testWidgets('the pair fits on a phone-width screen', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final (_, viewModel) = await pumpHome(tester);
    await startRun(tester, viewModel);

    expect(tester.takeException(), isNull,
        reason: 'a row of controls that overflows renders as a yellow-black '
            'stripe, and this is the width a phone actually has');
    expect(stopButton(tester), isNotNull);

    viewModel.dispose();
  });
}
