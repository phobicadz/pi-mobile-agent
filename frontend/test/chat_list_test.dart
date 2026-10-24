import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/chat_list.dart';
import 'package:provider/provider.dart';

/// Replays canned backend frames without a WebSocket or any HTTP.
class FakeChatService extends PiService {
  final StreamController<PiEvent> _events = StreamController<PiEvent>.broadcast();

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => _events.stream;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));

  void addUserMessage(String text) {
    emit({
      'type': 'message_start',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text}
        ],
      },
    });
  }
}

void main() {
  Future<PiViewModel> pumpChat(WidgetTester tester) async {
    final service = FakeChatService();
    final viewModel = PiViewModel(piService: service);

    await tester.pumpWidget(
      ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 400, child: ChatList(key: GlobalKey())),
          ),
        ),
      ),
    );

    // Lets the coalesced notification land, then lets any scroll animation
    // finish before the position is read.
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    return viewModel;
  }

  ScrollPosition chatPosition(WidgetTester tester) =>
      tester
          .widget<Scrollable>(find.byType(Scrollable).first)
          .controller!
          .position;

  Future<void> fillChat(WidgetTester tester, PiViewModel viewModel) async {
    for (var i = 0; i < 8; i++) {
      viewModel.setUserInput('message number $i with enough text to make the '
          'bubble tall enough that the list actually scrolls');
      await viewModel.submitPrompt();
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the chat sticks to the newest message', (tester) async {
    final viewModel = await pumpChat(tester);
    await fillChat(tester, viewModel);

    final position = chatPosition(tester);
    expect(position.pixels, greaterThan(0),
        reason: 'the fixture must actually be scrollable');
    expect(position.pixels, closeTo(position.maxScrollExtent, 1),
        reason: 'new messages must keep the newest one on screen');
    expect(find.byType(FloatingActionButton), findsNothing,
        reason: 'no jump button while already following the chat');

    viewModel.dispose();
  });

  testWidgets('scrolling up stops auto-follow, and the jump button returns',
      (tester) async {
    final viewModel = await pumpChat(tester);
    await fillChat(tester, viewModel);

    // Drag the content down: the user is scrolling back to read older messages.
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    final scrolledUp = chatPosition(tester).pixels;

    await fillChat(tester, viewModel);

    expect(find.byType(FloatingActionButton), findsOneWidget,
        reason: 'the user left the bottom, so offer a way back to it');
    expect(chatPosition(tester).pixels, lessThan(scrolledUp + 50),
        reason: 'new messages must not yank the reader back down');

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final position = chatPosition(tester);
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
    expect(find.byType(FloatingActionButton), findsNothing);

    viewModel.dispose();
  });
}
