import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/main.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

/// A live connection, so the app bar renders its actions instead of the
/// connecting screen.
class FakeService extends PiService {
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
}

/// Pump the app the way main.dart does, theme provider included.
Future<AppearanceController> pumpApp(WidgetTester tester,
    {Size size = const Size(900, 1200)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final appearance = AppearanceController();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppearanceController>.value(
      value: appearance,
      child: MyApp(
        service: FakeService(),
        safeArea: ValueNotifier<EdgeInsets>(EdgeInsets.zero),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return appearance;
}

/// Press the theme button and let the change land.
///
/// MaterialApp animates from one theme into the other, so checking the frame
/// right after the press still sees the theme that was there before it.
Future<void> pressThemeButton(WidgetTester tester, IconData offering) async {
  await tester.tap(find.byIcon(offering));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Brightness brightnessOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(AppBar).first)).brightness;

  testWidgets('the theme button switches the whole app to dark',
      (tester) async {
    final appearance = await pumpApp(tester);

    // The test surface is light, and the app starts by following it.
    expect(appearance.themeMode, ThemeMode.system);
    expect(brightnessOf(tester), Brightness.light);
    expect(find.byIcon(Icons.dark_mode), findsOneWidget,
        reason: 'the button offers the thing the screen is not');

    await pressThemeButton(tester, Icons.dark_mode);

    expect(appearance.themeMode, ThemeMode.dark);
    expect(brightnessOf(tester), Brightness.dark,
        reason: 'the theme MaterialApp builds with, not the colours of one '
            'widget inside it');
    expect(find.byIcon(Icons.dark_mode), findsNothing);
    expect(find.byIcon(Icons.light_mode), findsOneWidget);

    appearance.dispose();
  });

  testWidgets('the button switches back to light', (tester) async {
    final appearance = await pumpApp(tester);

    await pressThemeButton(tester, Icons.dark_mode);
    expect(brightnessOf(tester), Brightness.dark);

    await pressThemeButton(tester, Icons.light_mode);

    expect(appearance.themeMode, ThemeMode.light);
    expect(brightnessOf(tester), Brightness.light);
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);

    appearance.dispose();
  });

  testWidgets('the app bar still fits a phone with the theme button in it',
      (tester) async {
    // Four actions on a 390 logical pixel wide bar overflowed it by 29px the
    // moment the theme button went in, which is content that cannot be seen.
    final appearance = await pumpApp(tester, size: const Size(390, 844));

    expect(tester.takeException(), isNull,
        reason: 'the bar has to hold the new button on a phone as well as on a '
            'desktop');

    appearance.dispose();
  });
}
