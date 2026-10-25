import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/turn_progress.dart';
import 'package:provider/provider.dart';

/// Replays canned backend frames without a WebSocket.
class FakeProgressService extends PiService {
  final StreamController<PiEvent> _events = StreamController<PiEvent>.broadcast();

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => _events.stream;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

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
}

void main() {
  Future<PiViewModel> pumpBar(WidgetTester tester, PiService service) async {
    final viewModel = PiViewModel(piService: service);
    await tester.pumpWidget(
      ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          home: Scaffold(
            body: Column(children: const [TurnProgressBar()]),
          ),
        ),
      ),
    );
    return viewModel;
  }

  testWidgets('the bar shows what Pi is doing and how many tokens it has used',
      (tester) async {
    final service = FakeProgressService();
    await pumpBar(tester, service);

    // Nothing is running: the input area must stay exactly as it was.
    expect(find.byType(TurnProgressBar), findsOneWidget);
    expect(find.textContaining('tok out'), findsNothing);

    service.emit({'type': 'agent_start'});
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
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('thinking'), findsOneWidget,
        reason: 'a reasoning-only stretch must look like progress');
    expect(find.textContaining('tok out'), findsOneWidget);
    expect(find.textContaining('ctx'), findsOneWidget);

    service.emit({
      'type': 'tool_execution_start',
      'toolCallId': 'call_1',
      'toolName': 'read',
      'args': {'path': '/home/chamb/app/src/index.ts'},
    });
    service.emit({
      'type': 'tool_execution_update',
      'toolCallId': 'call_1',
      'toolName': 'read',
      'args': <String, dynamic>{},
      'partialResult': {
        'content': [
          {'type': 'text', 'text': 'x' * 5000}
        ]
      },
    });
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('read index.ts'), findsOneWidget);
    expect(find.textContaining('chars'), findsOneWidget,
        reason: 'a file read in flight shows how far it has got');

    service.emit({'type': 'agent_end'});
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('tok out'), findsNothing,
        reason: 'the line is removed when the run is over');
  });

  testWidgets('an estimate is marked as an estimate', (tester) async {
    final service = FakeProgressService();
    await pumpBar(tester, service);

    service.emit({'type': 'agent_start'});
    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    // A provider that reports no usage while streaming.
    service.emit({
      'type': 'message_update',
      'assistantMessageEvent': {'type': 'thinking_delta', 'delta': 'x' * 800},
    });
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('~200 tok out'), findsOneWidget,
        reason: 'an estimated count must not be mistaken for Pi\'s numbers');
  });
}
