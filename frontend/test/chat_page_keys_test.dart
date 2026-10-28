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

/// Replays canned backend frames; the prompt send succeeds so the chat stays in
/// a normal (non-error) state while it is being scrolled.
class FakeScrollChatService extends PiService {
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
  /// the chat only exists once the service reports a connection.
  @override
  bool get isConnected => true;
}

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

  Future<PiViewModel> pumpHome(WidgetTester tester) async {
    // PageUp/PageDown are wired up only where a desktop keyboard exists, and the
    // test default platform is mobile.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final service = FakeScrollChatService();
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

    for (var i = 0; i < 12; i++) {
      viewModel.setUserInput('message $i with enough text to make the bubble '
          'tall enough that the chat actually scrolls');
      await viewModel.submitPrompt();
      await tester.pump(const Duration(milliseconds: 120));
    }
    await settle(tester);
    return viewModel;
  }

  ScrollPosition chatPosition(WidgetTester tester) => tester
      .widget<Scrollable>(find.byType(Scrollable).first)
      .controller!
      .position;

  Future<double> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.pump();
    return chatPosition(tester).pixels;
  }

  testWidgets('PageDown then PageUp scroll the chat a viewport at a time',
      (tester) async {
    final viewModel = await pumpHome(tester);

    final start = chatPosition(tester).pixels;
    final viewport = chatPosition(tester).viewportDimension;
    expect(start, greaterThan(0), reason: 'the fixture must be scrollable');

    final up = await press(tester, LogicalKeyboardKey.pageUp);
    expect(up, lessThan(start), reason: 'PageUp moves the chat up');
    expect(start - up, closeTo(viewport * 0.9, 1),
        reason: 'one page is a viewport, with a little overlap for context');

    final down = await press(tester, LogicalKeyboardKey.pageDown);
    expect(down, greaterThan(up), reason: 'PageDown moves it back down');
    expect(down, closeTo(start, 1), reason: 'the two keys are symmetric');

    // Reset inline: flutter_test checks the foundation debug variables at the end
    // of the test body, before tearDown runs.
    debugDefaultTargetPlatformOverride = null;
    viewModel.dispose();
  });

  testWidgets('paging stops at the ends instead of claiming keys for nothing',
      (tester) async {
    final viewModel = await pumpHome(tester);

    var previous = chatPosition(tester).pixels;
    for (var i = 0; i < 12; i++) {
      final next = await press(tester, LogicalKeyboardKey.pageUp);
      if (next == previous) {
        expect(next, closeTo(0, 1),
            reason: 'the only place paging can stop is the top');
        break;
      }
      previous = next;
    }

    // Pressing PageUp at the very top must not move anything, and must not
    // pretend to have handled the key.
    final stuck = await press(tester, LogicalKeyboardKey.pageUp);
    expect(stuck, closeTo(0, 1));

    // Paging back down to the bottom resumes following the live chat, so a new
    // message pulls the reader along again.
    for (var i = 0; i < 12; i++) {
      final next = await press(tester, LogicalKeyboardKey.pageDown);
      if (next == previous) break;
      previous = next;
    }
    final bottom = chatPosition(tester);
    expect(bottom.pixels, closeTo(bottom.maxScrollExtent, 1));

    viewModel.setUserInput('a new reply arrives while following the chat');
    await viewModel.submitPrompt();
    await tester.pump(const Duration(milliseconds: 150));
    await settle(tester);
    final followed = chatPosition(tester);
    expect(followed.pixels, closeTo(followed.maxScrollExtent, 1),
        reason: 'paging back to the bottom re-attaches to the live chat');

    debugDefaultTargetPlatformOverride = null;
    viewModel.dispose();
  });

  testWidgets('the page keys are not registered on a touch platform',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final service = FakeScrollChatService();
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
    for (var i = 0; i < 12; i++) {
      viewModel.setUserInput('message $i with enough text to make the bubble '
          'tall enough that the chat actually scrolls');
      await viewModel.submitPrompt();
      await tester.pump(const Duration(milliseconds: 120));
    }
    await settle(tester);

    final before = chatPosition(tester).pixels;
    await press(tester, LogicalKeyboardKey.pageUp);
    expect(chatPosition(tester).pixels, closeTo(before, 1),
        reason: 'no physical page keys on a phone, so nothing is claimed here');

    debugDefaultTargetPlatformOverride = null;
    viewModel.dispose();
  });
}
