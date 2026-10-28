import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/main.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/theme_controller.dart';
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
Future<ThemeController> pumpApp(WidgetTester tester,
    {Size size = const Size(900, 1200)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final theme = ThemeController();
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MyApp(
        service: FakeService(),
        safeArea: ValueNotifier<EdgeInsets>(EdgeInsets.zero),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return theme;
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
    final theme = await pumpApp(tester);

    // The test surface is light, and the app starts by following it.
    expect(theme.mode, ThemeMode.system);
    expect(brightnessOf(tester), Brightness.light);
    expect(find.byIcon(Icons.dark_mode), findsOneWidget,
        reason: 'the button offers the thing the screen is not');

    await pressThemeButton(tester, Icons.dark_mode);

    expect(theme.mode, ThemeMode.dark);
    expect(brightnessOf(tester), Brightness.dark,
        reason: 'the theme MaterialApp builds with, not the colours of one '
            'widget inside it');
    expect(find.byIcon(Icons.dark_mode), findsNothing);
    expect(find.byIcon(Icons.light_mode), findsOneWidget);

    theme.dispose();
  });

  testWidgets('the button switches back to light', (tester) async {
    final theme = await pumpApp(tester);

    await pressThemeButton(tester, Icons.dark_mode);
    expect(brightnessOf(tester), Brightness.dark);

    await pressThemeButton(tester, Icons.light_mode);

    expect(theme.mode, ThemeMode.light);
    expect(brightnessOf(tester), Brightness.light);
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);

    theme.dispose();
  });

  testWidgets('the app bar still fits a phone with the theme button in it',
      (tester) async {
    // Four actions on a 390 logical pixel wide bar overflowed it by 29px the
    // moment the theme button went in, which is content that cannot be seen.
    final theme = await pumpApp(tester, size: const Size(390, 844));

    expect(tester.takeException(), isNull,
        reason: 'the bar has to hold the new button on a phone as well as on a '
            'desktop');

    theme.dispose();
  });
}
