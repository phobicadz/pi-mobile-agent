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

  /// The glow around the live bubble.
  ///
  /// Nothing else in the chat paints a shadow with a spread, so a match here is
  /// the glow and not some card that happens to be drawn with a Container.
  bool glows(Widget widget) =>
      widget is Container &&
      (widget.decoration as BoxDecoration?)
              ?.boxShadow
              ?.any((shadow) => shadow.spreadRadius > 0) ==
          true;

  double glowSpread(WidgetTester tester) =>
      (tester.widget<Container>(find.byWidgetPredicate(glows)).decoration
              as BoxDecoration)
          .boxShadow!
          .first
          .spreadRadius;

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
    expect(statusIcon(tester), Icons.psychology,
        reason: 'brain while it reasons');
    expect(find.text('thinking'), findsOneWidget);

    service.emit({
      'type': 'message_update',
      'assistantMessageEvent': {'type': 'text_delta', 'delta': 'hello'},
    });
    await tester.pump(const Duration(milliseconds: 150));
    expect(statusIcon(tester), Icons.draw,
        reason: 'pad and pen while it writes');

    service.toolStart('c1', 'read', {'path': '/home/adam/app/src/index.ts'});
    await tester.pump(const Duration(milliseconds: 150));
    expect(statusIcon(tester), Icons.menu_book,
        reason: 'book while it reads a file');
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

  testWidgets('the reply being written glows, and a finished one does not',
      (tester) async {
    final service = FakeStatusService();
    await pumpChat(tester, service);
    await start(service);

    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    service.emit({
      'type': 'message_update',
      'assistantMessageEvent': {'type': 'text_delta', 'delta': 'working'},
    });
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byWidgetPredicate(glows), findsOneWidget,
        reason:
            'the live bubble has to be findable in a wall of finished text');

    // A breathing glow is not a static border: the spread has to be moving.
    final before = glowSpread(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(glowSpread(tester), isNot(before),
        reason: 'the cue is an animation, not a highlight in a fixed shape');

    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'done'}
        ],
      },
    });
    service.emit({'type': 'agent_end', 'messages': []});
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byWidgetPredicate(glows), findsNothing,
        reason: 'a glow left behind a finished chat repaints it forever');
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
        reason:
            'the activity icon replaced the spinner; two indicators is one too many');
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
    expect(find.textContaining('tok'), findsNothing,
        reason: 'a finished reply carries no counters of its own either');
  });

  testWidgets('the counters show generation speed and nothing else',
      (tester) async {
    final service = FakeStatusService();
    await pumpChat(tester, service);
    await start(service);
    await tester.pump(const Duration(milliseconds: 150));

    // One response, finished, with the generation time Pi measured for it.
    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    service.thinking('hmm' * 400);
    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'assistant',
        'content': <dynamic>[],
        'usage': {
          'input': 10,
          'output': 224,
          'cacheRead': 5870,
          'totalTokens': 6104,
          'reasoning': 168,
          'cost': {'total': 0.0085},
        },
        'durationMs': 4000,
      },
    });

    // The next response is the one carrying a status line, and the generation
    // time already measured in this run is what its speed is divided by.
    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
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

    expect(find.textContaining('tok/s'), findsOneWidget,
        reason: 'speed is the figure the status line carries');
    for (final removed in ['tok out', 'ctx', 'chars', '%']) {
      expect(find.textContaining(removed), findsNothing,
          reason: '$removed was read from figures the backend does not report '
              'reliably, so a run could show numbers that were not describing it');
    }
  });

  testWidgets(
    'no speed is claimed before the model has been generating long enough to measure',
    (tester) async {
      final service = FakeStatusService();
      await pumpChat(tester, service);
      await start(service);

      service.emit({
        'type': 'message_start',
        'message': {'role': 'assistant', 'content': <Object>[]},
      });
      // A provider that reports no usage while streaming (local models often
      // do), which is the case the old `~` estimate marker existed to cover.
      service.thinking('x' * 800);
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('starting…'), findsOneWidget,
          reason: 'the request is sent and nothing has been timed yet; a '
              'number this early would read as a measurement');
      expect(find.textContaining('tok/s'), findsNothing);
    },
  );
}
