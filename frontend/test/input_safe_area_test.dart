import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/main.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

/// A service that reports a live connection, so HomeScreen renders the chat and
/// the prompt panel instead of the connecting spinner.
class FakeService extends PiService {
  final _events = StreamController<PiEvent>.broadcast();

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
}

/// iPhone-shaped surface, logical pixels.
const phoneSize = Size(390, 844);

/// What an installed PWA on a notched iPhone reports once the page is allowed to
/// draw under the status bar and the home indicator (see
/// lib/utils/browser_viewport_web.dart).
const notchedInsets = EdgeInsets.only(top: 44, left: 0, right: 0, bottom: 34);

/// Pump the real app the way main.dart does, with the safe areas the browser
/// reported.
Future<void> pumpApp(WidgetTester tester, EdgeInsets insets,
    {Size size = phoneSize}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // The theme provider is part of how the app is built now, not an optional
  // extra: MyApp is the widget that builds MaterialApp, and MaterialApp needs to
  // be told which theme to build with.
  await tester.pumpWidget(ChangeNotifierProvider<AppearanceController>.value(
    value: AppearanceController(),
    child: MyApp(
      service: FakeService(),
      safeArea: ValueNotifier<EdgeInsets>(insets),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the prompt panel dips into the home-indicator band',
      (tester) async {
    await pumpApp(tester, notchedInsets);

    final field = tester.getRect(find.byType(TextField));
    final screen = tester.getRect(find.byType(Scaffold));

    // The band is a swipe zone, not a dead zone: the field reaches 12px into it
    // instead of being pushed a whole 34px band above it. It was 50 while a
    // fixed 16 was stacked on top of the inset.
    expect(screen.bottom - field.bottom, notchedInsets.bottom - 12);

    // ...and it still keeps 10px clear of the very bottom, where a tap would
    // compete with the home gesture.
    expect(screen.bottom - field.bottom, greaterThanOrEqualTo(10));
    expect(field.bottom, lessThan(screen.bottom));
  });

  testWidgets('a browser that reports no insets keeps only a small margin',
      (tester) async {
    await pumpApp(tester, EdgeInsets.zero);

    final field = tester.getRect(find.byType(TextField));
    final screen = tester.getRect(find.byType(Scaffold));

    // The dip is off the inset, so with no inset there is nothing to dip into:
    // the floor is what the field keeps.
    expect(screen.bottom - field.bottom, 10);
  });

  testWidgets(
      'side insets in landscape are not crowded out by the fixed padding',
      (tester) async {
    await pumpApp(
      tester,
      const EdgeInsets.only(top: 0, left: 47, right: 47, bottom: 21),
      size: const Size(844, 390),
    );

    final field = tester.getRect(find.byType(TextField));
    final screen = tester.getRect(find.byType(Scaffold));
    expect(field.left, greaterThanOrEqualTo(47),
        reason:
            'the notch side inset has to beat the 16 the panel uses otherwise');
    expect(field.right, lessThanOrEqualTo(844 - 47));
    // A 21px inset dips to 9, which is under the floor: the floor wins.
    expect(screen.bottom - field.bottom, 10);
  });
}
