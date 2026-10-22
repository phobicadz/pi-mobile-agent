import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';

/// PiService stub that replays canned backend frames instead of a WebSocket.
class FakePiService extends PiService {
  final _events = StreamController<PiEvent>.broadcast();
  Stream<PiState> get stateUpdates => const Stream.empty();
  Stream<PiEvent> get events => _events.stream;

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));
}

/// PiService stub whose resume command returns canned saved history.
class FakeResumeService extends FakePiService {
  final List<Map<String, dynamic>> history;
  String? resumedPath;

  FakeResumeService(this.history);

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<List<Map<String, dynamic>>> resumeSession(String sessionPath) async {
    resumedPath = sessionPath;
    return history;
  }
}

void main() {
  test('Pi event stream becomes chat messages', () async {
    final service = FakePiService();
    final vm = PiViewModel(piService: service);

    // Same sequence captured from the live backend.
    service.emit({
      'type': 'message_start',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Say hello'}
        ],
        'timestamp': 1792693211356,
      },
    });
    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Say hello'}
        ],
        'timestamp': 1792693211356,
      },
    });
    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <dynamic>[]},
    });
    service.emit({
      'type': 'message_update',
      'assistantMessageEvent': {
        'type': 'text_delta',
        'contentIndex': 0,
        'delta': 'Hello there, ',
      },
    });
    service.emit({
      'type': 'message_update',
      'assistantMessageEvent': {
        'type': 'text_delta',
        'contentIndex': 0,
        'delta': 'friend!',
      },
    });
    service.emit({
      'type': 'message_update',
      'assistantMessageEvent': {
        'type': 'toolcall_end',
        'contentIndex': 1,
        'id': 'toolu_1',
        'toolCall': {
          'type': 'toolCall',
          'id': 'toolu_1',
          'name': 'bash',
          'arguments': {'command': 'ls'},
        },
      },
    });
    service.emit({
      'type': 'tool_execution_start',
      'toolCallId': 'toolu_1',
      'toolName': 'bash',
      'args': {'command': 'ls'},
    });
    service.emit({
      'type': 'tool_execution_end',
      'toolCallId': 'toolu_1',
      'toolName': 'bash',
      'result': {
        'content': [
          {'type': 'text', 'text': 'file1\nfile2'}
        ],
      },
    });
    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'Hello there, friend!'}
        ],
      },
    });
    service.emit({'type': 'agent_end', 'messages': []});

    await Future<void>.delayed(Duration.zero);

    expect(vm.messages.length, 2, reason: 'one user + one assistant message');
    expect(vm.messages[0].role, 'user');
    expect(vm.messages[0].content, 'Say hello');
    expect(vm.messages[1].role, 'assistant');
    expect(vm.messages[1].content, 'Hello there, friend!');
    expect(vm.messages[1].streaming, isFalse);
    expect(vm.messages[1].toolCalls.length, 1, reason: 'tool call not duplicated');
    expect(vm.messages[1].toolCalls.single.name, 'bash');
    expect(vm.messages[1].toolCalls.single.result, 'file1\nfile2');
    expect(vm.isLoading, isFalse);

    vm.dispose();
  });

  // Each theme needs its own test: re-pumping a widget tree with a changed
  // themeMode does not re-resolve the inherited theme.
  Future<void> pumpBubble(WidgetTester tester, ThemeMode mode) async {
    final message = PiMessage(
      id: 'm1',
      role: 'assistant',
      content: 'Hello there, friend!',
      timestamp: DateTime.now(),
    );
    await tester.pumpWidget(MaterialApp(
      themeMode: mode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue, brightness: Brightness.light),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue, brightness: Brightness.dark),
      ),
      home: Scaffold(body: ChatBubble(message: message)),
    ));
  }

  testWidgets('chat text is dark in the light theme', (tester) async {
    await pumpBubble(tester, ThemeMode.light);
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.style!.color!.computeLuminance(), lessThan(0.2),
        reason: 'light theme text must be dark');
  });

  testWidgets('chat text is light in the dark theme', (tester) async {
    await pumpBubble(tester, ThemeMode.dark);
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.style!.color!.computeLuminance(), greaterThan(0.6),
        reason: 'dark theme text must be light');
  });

  test('resumeSession hydrates saved history from get_messages shape',
      () async {
    // Records shaped like Pi's session messages (what get_messages returns).
    final service = FakeResumeService([
      {
        'id': 'u1',
        'role': 'user',
        'timestamp': 1792693211356,
        'content': [
          {'type': 'text', 'text': 'Build me a scraper'}
        ],
      },
      {
        'id': 'a1',
        'role': 'assistant',
        'timestamp': 1792693220000,
        'content': [
          {'type': 'thinking', 'thinking': 'hmm'},
          {'type': 'text', 'text': 'Here is the scraper.'},
          {
            'type': 'toolCall',
            'id': 'toolu_9',
            'name': 'write',
            'arguments': {'path': 'scraper.py'},
          },
        ],
      },
      {
        'id': 't1',
        'role': 'toolResult',
        'toolCallId': 'toolu_9',
        'toolName': 'write',
        'content': [
          {'type': 'text', 'text': 'wrote 120 lines'}
        ],
      },
    ]);
    final vm = PiViewModel(piService: service);

    await vm.resumeSession('/sessions/abc.jsonl');

    expect(service.resumedPath, '/sessions/abc.jsonl');
    expect(vm.error, isNull, reason: 'loadModels failure must not leak here');
    expect(vm.messages.length, 2);
    expect(vm.messages[0].role, 'user');
    expect(vm.messages[0].content, 'Build me a scraper');
    expect(vm.messages[1].role, 'assistant');
    expect(vm.messages[1].content, 'Here is the scraper.');
    expect(vm.messages[1].toolCalls.single.name, 'write');
    expect(vm.messages[1].toolCalls.single.result, 'wrote 120 lines');
    expect(vm.isLoading, isFalse);

    vm.dispose();
  });

  test('PiState parses the model object', () {
    final state = PiState.fromJson({
      'model': {'id': 'claude-sonnet-5'},
      'messageCount': 11,
      'isStreaming': false,
    });
    expect(state.currentModel, 'claude-sonnet-5');
    expect(state.messageCount, 11);
  });
}
