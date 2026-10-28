import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/main.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/theme_controller.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

/// A service whose connection state is whatever the test asked for.
class FakeService extends PiService {
  FakeService({required this.connected});

  final bool connected;

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => const Stream.empty();

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  bool get isConnected => connected;

  @override
  Future<void> refreshState() async {}
}

/// The connection dot, found by what it is rather than by where it sits - a
/// coloured circle in the app bar is the only thing in the app shaped like it.
Finder connectionDot() => find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).shape == BoxShape.circle,
    );

Color? dotColour(WidgetTester tester) {
  final decoration = tester.widget<Container>(connectionDot().first).decoration
      as BoxDecoration;
  return decoration.color;
}

Future<void> pumpApp(WidgetTester tester, {required bool connected}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: ThemeController(),
      child: MyApp(
        service: FakeService(connected: connected),
        safeArea: ValueNotifier<EdgeInsets>(EdgeInsets.zero),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the app bar shows a green dot when the agent is reachable',
      (tester) async {
    await pumpApp(tester, connected: true);

    expect(dotColour(tester), Colors.green);
    expect(find.text('Connected'), findsNothing,
        reason: 'the colour is the whole message now; the word was the part of '
            'the app bar a phone could not afford');
  });

  testWidgets('the app bar shows a red dot when it is not', (tester) async {
    await pumpApp(tester, connected: false);

    expect(dotColour(tester), Colors.red);
    expect(find.text('Disconnected'), findsNothing);
  });

  testWidgets('the words are still there for anyone who asks the dot',
      (tester) async {
    await pumpApp(tester, connected: true);

    expect(find.byTooltip('Connected'), findsOneWidget,
        reason: 'a dot with no label available anywhere is a dot nobody can be '
            'sure about');
  });
}
