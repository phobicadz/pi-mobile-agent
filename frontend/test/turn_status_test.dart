import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';
import 'package:pi_mobile_agent/widgets/chat_list.dart';
import 'package:pi_mobile_agent/widgets/turn_status.dart';
import 'package:provider/provider.dart';

/// Replays canned backend frames without a WebSocket, and answers the session
/// stats call the way a real backend does.
class FakeStatusService extends PiService {
  final StreamController<PiEvent> _events = StreamController<PiEvent>.broadcast();

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => _events.stream;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<void> sendPrompt(String message) async {}

  @override
  Future<PiSessionStats> getSessionStats() async => PiSessionStats.fromJson({
        'tokens': {'input': 50000, 'output': 10000, 'total': 105000},
        'cost': 0.45,
        'contextUsage': {
          'tokens': 60000,
          'contextWindow': 200000,
          'percent': 30,
        },
      });

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));

  void thinking(String delta) => emit({
        'type': 'message_update',
        'assistantMessageEvent': {'type': 'thinking_delta', 'delta': delta},
      });

  void toolStart(String id, String name, Map<String, dynamic> args) => emit({
        'type': 'tool_execution_start',
        'toolCallId': id,
        'toolName': name,
        'args': args,
      });
}

void main() {
  late PiViewModel viewModel;

  Future<void> pumpChat(WidgetTester tester, FakeStatusService service) async {
    viewModel = PiViewModel(piService: service);
    await tester.pumpWidget(
      ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 600, child: ChatList(key: GlobalKey())),
          ),
        ),
      ),
    );
  }

  Future<void> start(FakeStatusService service) async {
    viewModel.setUserInput('do something');
    await viewModel.submitPrompt();
  }

  /// The icon the status line is showing.
  IconData? statusIcon(WidgetTester tester) => tester
      .widget<Icon>(find
          .descendant(
            of: find.byType(TurnStatusRow),
            matching: find.byType(Icon),
          )
          .first)
      .icon;

  testWidgets('the busy icon matches what Pi is doing', (tester) async {
    final service = FakeStatusService();
    await pumpChat(tester, service);
    await start(service);
    await tester.pump(const Duration(milliseconds: 150));

    expect(statusIcon(tester), Icons.hourglass_top,
        reason: 'nothing has arrived yet: waiting is what is happening');

    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    service.thinking('pondering');
    await tester.pump(const Duration(milliseconds: 150));
    expect(statusIcon(tester), Icons.psychology, reason: 'brain while it reasons');
    expect(find.text('thinking'), findsOneWidget);

    service.emit({
      'type': 'message_update',
      'assistantMessageEvent': {'type': 'text_delta', 'delta': 'hello'},
    });
    await tester.pump(const Duration(milliseconds: 150));
    expect(statusIcon(tester), Icons.draw, reason: 'pad and pen while it writes');

    service.toolStart('c1', 'read', {'path': '/home/adam/app/src/index.ts'});
    await tester.pump(const Duration(milliseconds: 150));
    expect(statusIcon(tester), Icons.menu_book, reason: 'book while it reads a file');
    expect(find.text('read index.ts'), findsOneWidget);

    service.toolStart('c2', 'write', {'path': 'notes.md'});
    await tester.pump(const Duration(milliseconds: 150));
    expect(statusIcon(tester), Icons.edit_note);

    service.toolStart('c3', 'bash', {'command': 'npm test'});
    await tester.pump(const Duration(milliseconds: 150));
    expect(statusIcon(tester), Icons.terminal);
    expect(find.text('bash npm test'), findsOneWidget);

    service.toolStart('c4', 'grep', {'pattern': 'formatTokens'});
    await tester.pump(const Duration(milliseconds: 150));
    expect(statusIcon(tester), Icons.search);

    service.toolStart('c5', 'whatever_tool', {});
    await tester.pump(const Duration(milliseconds: 150));
    expect(statusIcon(tester), Icons.build,
        reason: 'an unknown tool still gets a tool icon, not a spinner');
  });

  testWidgets('there is exactly one busy indicator and it is inside the bubble',
      (tester) async {
    final service = FakeStatusService();
    await pumpChat(tester, service);
    await start(service);
    await tester.pump(const Duration(milliseconds: 150));

    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    service.thinking('hmm');
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the activity icon replaced the spinner; two indicators is one too many');
    expect(
      find.descendant(
        of: find.byType(ChatBubble),
        matching: find.byType(TurnStatusRow),
      ),
      findsOneWidget,
      reason: 'the status belongs to the reply it describes');

    service.emit({
      'type': 'message_update',
      'assistantMessageEvent': {'type': 'text_delta', 'delta': 'done'},
    });
    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'done'}
        ],
        'usage': {
          'input': 10,
          'output': 224,
          'totalTokens': 6104,
          'reasoning': 168,
          'cost': {'total': 0.0085},
        },
      },
    });
    service.emit({'type': 'agent_end', 'messages': []});
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byType(TurnStatusRow), findsNothing,
        reason: 'a finished reply shows no activity at all');
    expect(find.text('224 tok (thinking)'), findsOneWidget,
        reason: 'what it cost stays on the bubble');
  });

  testWidgets('the counters show tokens, tool progress and context use',
      (tester) async {
    final service = FakeStatusService();
    await pumpChat(tester, service);
    await start(service);
    await tester.pump(const Duration(milliseconds: 150));

    // First run, which settles and pulls the session totals.
    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    service.thinking('hmm' * 400);
    service.emit({'type': 'agent_end', 'messages': []});
    service.emit({'type': 'agent_settled'});
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(TurnStatusRow), findsNothing);

    // Second run: the context usage Pi reported is now available to show.
    await start(service);
    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    service.emit({
      'type': 'message_update',
      'usage': {
        'input': 10,
        'output': 4,
        'cacheRead': 5870,
        'totalTokens': 5884,
        'cost': {'total': 0.0074},
      },
      'assistantMessageEvent': {'type': 'thinking_delta', 'delta': 'hmm' * 400},
    });
    service.toolStart('c1', 'read', {'path': 'big.log'});
    service.emit({
      'type': 'tool_execution_update',
      'toolCallId': 'c1',
      'toolName': 'read',
      'args': <String, dynamic>{},
      'partialResult': {
        'content': [
          {'type': 'text', 'text': 'x' * 5000}
        ]
      },
    });
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('tok out'), findsOneWidget);
    expect(find.textContaining('ctx'), findsOneWidget);
    expect(find.textContaining('5.0k chars'), findsOneWidget,
        reason: 'a file read in flight shows how far it has got');
    expect(find.textContaining('30%'), findsOneWidget,
        reason: 'context use from get_session_stats');
  });

  testWidgets('an estimated count is marked as an estimate', (tester) async {
    final service = FakeStatusService();
    await pumpChat(tester, service);
    await start(service);
    await tester.pump(const Duration(milliseconds: 150));

    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    // A provider that reports no usage while streaming (local models often do).
    service.thinking('x' * 800);
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('~200 tok out'), findsOneWidget,
        reason: 'an estimate must not be mistaken for Pi\'s numbers');
  });
}
