import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';
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

/// A service whose send succeeds, so the turn stays "running" instead of
/// failing on a missing WebSocket.
class _QuietChatService extends FakeChatService {
  @override
  Future<void> sendPrompt(String message) async {}
}

void main() {
  Future<PiViewModel> pumpChat(WidgetTester tester, {PiService? service}) async {
    final chatService = service ?? FakeChatService();
    final viewModel = PiViewModel(piService: chatService);

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

  testWidgets('a running turn with no text yet shows a thinking bubble',
      (tester) async {
    final service = _QuietChatService();
    final viewModel = await pumpChat(tester, service: service);

    // Pi has been told to work but has produced nothing: the chat must say so.
    viewModel.setUserInput('do something slow');
    await viewModel.submitPrompt();
    await tester.pump(const Duration(milliseconds: 120));
    expect(viewModel.messages.length, 1, reason: 'only the prompt is stored');
    expect(find.byType(ChatBubble), findsNWidgets(2),
        reason: 'the prompt plus a thinking indicator');
    expect(find.byType(CircularProgressIndicator), findsWidgets,
        reason: 'the indicator has to look alive, not like a stuck bubble');

    // Pi opens the assistant reply before any text arrives: the real bubble
    // takes over, so the indicator must not double up with it.
    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': []},
    });
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(ChatBubble), findsNWidgets(2),
        reason: 'no second indicator next to the real empty reply');

    service.emit({
      'type': 'message_update',
      'assistantMessageEvent': {'type': 'text_delta', 'delta': 'working on it'},
    });
    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'working on it'}
        ]
      },
    });
    service.emit({
      'type': 'tool_execution_start',
      'toolCallId': 't1',
      'toolName': 'bash',
      'args': {'command': 'sleep 5'},
    });
    service.emit({
      'type': 'tool_execution_end',
      'toolCallId': 't1',
      'result': {'content': [{'type': 'text', 'text': 'done'}]},
    });

    // A tool finished, so Pi is asking the model again. This second thinking
    // gap is the one users report as "the app went silent".
    service.emit({'type': 'turn_start'});
    await tester.pump(const Duration(milliseconds: 120));
    expect(viewModel.awaitingModel, isTrue);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    service.emit({'type': 'agent_end', 'messages': []});
    await tester.pump(const Duration(milliseconds: 120));
    expect(viewModel.awaitingModel, isFalse);
    expect(viewModel.messages.length, 2);
    expect(find.byType(ChatBubble), findsNWidgets(2),
        reason: 'prompt + finished reply, indicator gone');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    viewModel.dispose();
  });

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
