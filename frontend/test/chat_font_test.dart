import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/chat_list.dart';
import 'package:provider/provider.dart';

import 'support/app_menu.dart';

/// Replays canned backend frames so a prompt can be sent and the message it
/// produces renders in the chat like any other.
class FakeChatService extends PiService {
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

  @override
  bool get isConnected => true;
}

Future<(AppearanceController, PiViewModel)> pumpHome(
    WidgetTester tester) async {
  final service = FakeChatService();
  final appearance = AppearanceController();
  final viewModel = PiViewModel(piService: service);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppearanceController>.value(
      value: appearance,
      child: ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return (appearance, viewModel);
}

void main() {
  /// The size the chat text is actually rendered at, read out of the bubble
  /// rather than out of the setting - the setting being 1.3 means nothing if the
  /// bubble is still drawing 14.
  double chatTextSize(WidgetTester tester) => tester
      .widget<Text>(find
          .descendant(
            of: find.byType(ChatList),
            matching: find.text('plain text about the build'),
          )
          .first)
      .style!
      .fontSize!;

  Future<void> press(WidgetTester tester, IconData icon) async {
    // The size controls live in the menu the hamburger opens, and the menu stays
    // open while they are pressed - changing a size is something to see the
    // effect of before choosing the next one.
    final button = find.widgetWithIcon(IconButton, icon);
    await scrollMenuIntoView(tester, button);
    await tester.tap(button);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// One message, sent once, and left alone for the whole test.
  Future<void> oneMessage(WidgetTester tester, PiViewModel viewModel) async {
    await viewModel.submitPrompt('plain text about the build');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the text size buttons change the size the chat is drawn at',
      (tester) async {
    final (appearance, viewModel) = await pumpHome(tester);
    await oneMessage(tester, viewModel);
    await openAppMenu(tester);

    // The size the bubbles were laid out for.
    expect(chatTextSize(tester), closeTo(14, 0.001));

    await press(tester, Icons.text_increase);
    expect(chatTextSize(tester), closeTo(15.4, 0.001),
        reason: 'the message content never changed, so this is also the proof '
            'that the cached rendering is invalidated by the size - a cache '
            'keyed on content alone would still be drawing 14 here');

    await press(tester, Icons.text_decrease);
    await press(tester, Icons.text_decrease);
    expect(chatTextSize(tester), closeTo(12.6, 0.001));

    expect(appearance.fontScale, closeTo(0.9, 0.001));

    appearance.dispose();
    viewModel.dispose();
  });

  testWidgets('the buttons say so at the ends of the range', (tester) async {
    final (appearance, viewModel) = await pumpHome(tester);
    await oneMessage(tester, viewModel);
    await openAppMenu(tester);

    for (var i = 0; i < 12; i++) {
      await press(tester, Icons.text_increase);
    }
    expect(chatTextSize(tester), closeTo(25.2, 0.001),
        reason: 'the range ends somewhere, and text that keeps growing past a '
            'window is not a size control');

    final larger = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.text_increase));
    expect(larger.onPressed, isNull,
        reason: 'a button that does nothing at the end of the range reads as a '
            'broken button');

    for (var i = 0; i < 14; i++) {
      await press(tester, Icons.text_decrease);
    }
    expect(chatTextSize(tester), closeTo(11.2, 0.001));
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.text_decrease))
            .onPressed,
        isNull);

    appearance.dispose();
    viewModel.dispose();
  });

  testWidgets('the steps are exact sizes, not a running sum', (tester) async {
    final (appearance, _) = await pumpHome(tester);

    for (var i = 0; i < 3; i++) {
      appearance.changeFont(larger: true);
    }
    expect(appearance.fontScale, 1.3,
        reason: 'adding 0.1 three times is how 1.3 becomes 1.2999999999999998, '
            'and a size that does not match its stored value is its own bug');

    appearance.dispose();
  });
}
