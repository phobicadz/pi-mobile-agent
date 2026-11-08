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

/// A connected backend that can be told, on demand, that the agent has stopped
/// working — which is the state frame that ends a run.
class FinishableService extends PiService {
  final _states = StreamController<PiState>.broadcast();

  /// What the app asked the backend to set, in order.
  final requested = <bool>[];

  @override
  Stream<PiState> get stateUpdates => _states.stream;

  @override
  Stream<PiEvent> get events => const Stream.empty();

  /// The backend's own value, which a test can move to show what the switch
  /// does when a *different* device changes the setting.
  final _notificationsController = StreamController<bool>.broadcast();

  @override
  Stream<bool> get notificationUpdates => _notificationsController.stream;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  bool get isConnected => true;

  @override
  Future<void> sendPrompt(String message,
      {List<PiImage> images = const []}) async {}

  @override
  Future<void> setNotifications(bool enabled) async {
    requested.add(enabled);
  }

  @override
  Future<void> refreshState() async {}

  /// The frame Pi sends when a run is over.
  void endRun() => _states.add(PiState(isProcessing: false));

  /// What the backend pushes on connect and after any device moves the switch.
  void reportNotifications(bool enabled) =>
      _notificationsController.add(enabled);

  void close() {
    _states.close();
    _notificationsController.close();
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(FinishableService, PiViewModel)> pumpHome(WidgetTester tester) async {
  // A phone-sized window first, because this is a notice about the composer:
  // it has to fit a screen where the drawer and the send field compete for
  // room.
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final service = FinishableService();
  final viewModel = PiViewModel(piService: service);
  addTearDown(service.close);
  addTearDown(viewModel.dispose);

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

/// Type a prompt and send it the way a person does, so the run is one the
/// screen started rather than one a test handed the view model.
Future<void> sendPromptFromField(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'do the long thing');
  await settle(tester);
  await tester.tap(find.byIcon(Icons.send));
  await settle(tester);
}

/// Close the menu by pressing beside it, which is what a phone does.
Future<void> closeMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(380, 400));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the menu carries the notice switch and says what it is set to',
      (tester) async {
    await pumpHome(tester);

    await openAppMenu(tester);
    await scrollMenuIntoView(tester, find.textContaining('when the agent finishes'));

    expect(find.text('Notify me when the agent finishes'), findsOneWidget,
        reason: 'the notice is a setting with two states, so the menu has to '
            'name it rather than be an icon to guess at');

    // The notice row carries one control, and it is in the notice row - the
    // menu has another switch now, so "the switch in the drawer" is no longer
    // one thing.
    final switches = tester
        .widgetList<Switch>(menuSwitch('Notify me when the agent finishes'))
        .toList();
    expect(switches, hasLength(1));
    expect(switches.single.value, isTrue,
        reason: 'a notice you have to be able to reach is worth starting on; '
            'the app offers it until you say otherwise');

    await closeMenu(tester);
  });

  testWidgets('a run this app sent says when it is done', (tester) async {
    final (service, _) = await pumpHome(tester);

    await sendPromptFromField(tester);
    expect(find.text('Agent finished'), findsNothing,
        reason: 'while the run is going there is nothing to announce');

    service.endRun();
    await settle(tester);

    expect(find.text('Agent finished'), findsOneWidget,
        reason: 'the notice is the whole reason a long task can be started '
            'and walked away from');
  });

  testWidgets('switching it off silences the notice', (tester) async {
    final (service, _) = await pumpHome(tester);

    await openAppMenu(tester);
    await scrollMenuIntoView(tester, find.textContaining('when the agent finishes'));
    await tester.tap(menuSwitch('Notify me when the agent finishes'));
    await settle(tester);

    expect(find.text('No notice when the agent finishes'), findsOneWidget,
        reason: 'the row has to read as the state it is now in, not the one it '
            'was in when the menu was opened');

    await closeMenu(tester);

    await sendPromptFromField(tester);
    service.endRun();
    await settle(tester);

    expect(find.text('Agent finished'), findsNothing,
        reason: 'off has to mean off, including for the run that was already '
            'in flight when the switch was moved');
  });

  testWidgets('a run that was stopped is not announced', (tester) async {
    final (service, _) = await pumpHome(tester);

    await sendPromptFromField(tester);
    await tester.tap(find.byIcon(Icons.stop));
    await settle(tester);

    service.endRun();
    await settle(tester);

    expect(find.text('Agent finished'), findsNothing,
        reason: 'the person who pressed stop is the one thing that already '
            'knows the run ended');
  });

  testWidgets('pressing the switch asks the backend, which is what the agent acts on',
      (tester) async {
    final (service, _) = await pumpHome(tester);

    await openAppMenu(tester);
    await scrollMenuIntoView(tester, find.textContaining('when the agent finishes'));
    await tester.tap(menuSwitch('Notify me when the agent finishes'));
    await settle(tester);

    expect(service.requested, [false],
        reason: 'the notice is sent by the agent process, not this one, so a '
            'switch that only changed locally would silence nothing');
  });

  testWidgets('the switch shows what the backend says, including what another device set',
      (tester) async {
    final (service, _) = await pumpHome(tester);

    service.reportNotifications(false);
    await settle(tester);

    await openAppMenu(tester);
    await scrollMenuIntoView(tester, find.textContaining('when the agent finishes'));

    expect(find.text('No notice when the agent finishes'), findsOneWidget,
        reason: 'the setting is one thing the agent acts on, so a second device '
            'has to open on its real state rather than on its own default');
    expect(tester.widget<Switch>(menuSwitch('No notice when the agent finishes'))
        .value, isFalse);
  });
}
