import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/main.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';

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

  await tester.pumpWidget(MyApp(
    serverUrl: 'ws://example.test:3000',
    safeArea: ValueNotifier<EdgeInsets>(insets),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  // The service's command timeout is a real 30 s timer; let it fire so the test
  // framework does not find a pending timer at the end.
  await tester.pump(const Duration(seconds: 35));
}

void main() {
  testWidgets('the prompt panel reserves the home-indicator band and nothing more',
      (tester) async {
    await pumpApp(tester, notchedInsets);

    final field = tester.getRect(find.byType(TextField));
    final screen = tester.getRect(find.byType(Scaffold));

    // The field ends exactly where the home indicator begins. Stacking a fixed
    // 16 on top of the inset - what the app used to do - made this 50 and left
    // an empty band under the field on every phone with a home indicator.
    expect(screen.bottom - field.bottom, notchedInsets.bottom);

    // The panel itself still runs flush to the bottom edge of the screen, so
    // what was reclaimed goes to the chat instead of to a gap.
    expect(field.bottom, lessThan(screen.bottom));
  });

  testWidgets('a browser that reports no insets keeps only a small margin',
      (tester) async {
    await pumpApp(tester, EdgeInsets.zero);

    final field = tester.getRect(find.byType(TextField));
    final screen = tester.getRect(find.byType(Scaffold));

    expect(screen.bottom - field.bottom, 10);
  });

  testWidgets('side insets in landscape are not crowded out by the fixed padding',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.reset);

    await pumpApp(
      tester,
      const EdgeInsets.only(top: 0, left: 47, right: 47, bottom: 21),
      size: const Size(844, 390),
    );

    final field = tester.getRect(find.byType(TextField));
    expect(field.left, greaterThanOrEqualTo(47),
        reason: 'the notch side inset has to beat the 16 the panel uses otherwise');
    expect(field.right, lessThanOrEqualTo(844 - 47));
  });
}
