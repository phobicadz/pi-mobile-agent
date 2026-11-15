import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/models/turn_progress.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';

/// PiService stub that replays canned backend frames instead of a WebSocket -
/// the same shape as the one in `pi_view_model_test.dart`, because a compaction
/// is only testable end to end as a frame the backend relayed.
class FakePiService extends PiService {
  final _events = StreamController<PiEvent>.broadcast();
  Stream<PiState> get stateUpdates => const Stream.empty();
  @override
  Stream<PiEvent> get events => _events.stream;

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));
}

/// A compaction of the kind that actually happens in this app's own sessions:
/// auto, at the threshold, with a summary long enough to fold.
PiCompaction _threshold({
  String summary = '',
  int? before = 195702,
  int? after = 32100,
  String? errorMessage,
  bool aborted = false,
}) =>
    PiCompaction(
      reason: 'threshold',
      tokensBefore: before,
      tokensAfter: after,
      summary: summary,
      errorMessage: errorMessage,
      aborted: aborted,
    );

PiMessage _compaction(PiCompaction c) => PiMessage(
      id: 'compaction-1',
      role: 'system',
      content: '',
      timestamp: DateTime.utc(2026, 11, 10),
      compaction: c,
    );

/// A summary with [count] paragraphs, one per line, blank lines between them.
///
/// Paragraphs rather than one wrapped wall: the fold counts lines, and a test
/// that wants "line eight is hidden" needs a document whose lines are separate
/// blocks.
String _summary(int count) => List.generate(
        count, (i) => 'Paragraph ${i + 1} of the summary.').join('\n\n');

Future<void> _pump(WidgetTester tester, PiMessage message,
    {bool compact = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChatBubble(message: message, compact: compact),
        ),
      ),
    ),
  );
}

Map<String, dynamic> _endFrame({
  String reason = 'threshold',
  String summary = 'kept summary text',
  int tokensBefore = 195702,
  int? estimatedTokensAfter = 32100,
  String? errorMessage,
  bool aborted = false,
}) =>
    {
      'type': 'compaction_end',
      'reason': reason,
      'aborted': aborted,
      if (errorMessage != null) 'errorMessage': errorMessage,
      'result': {
        'summary': summary,
        'firstKeptEntryId': 'e-100',
        'tokensBefore': tokensBefore,
        if (estimatedTokensAfter != null)
          'estimatedTokensAfter': estimatedTokensAfter,
      },
    };

void main() {
  group('PiCompaction.fromEvent', () {
    test('reads the frame as Pi sends it', () {
      final c = PiCompaction.fromEvent(_endFrame(
        summary: 'The conversation was about X.',
        estimatedTokensAfter: 32100,
      ));
      expect(c.reason, 'threshold');
      expect(c.tokensBefore, 195702);
      expect(c.tokensAfter, 32100);
      expect(c.summary, 'The conversation was about X.');
      expect(c.failed, isFalse);
    });

    test('a stopped compaction has no result to read', () {
      final c = PiCompaction.fromEvent({
        'type': 'compaction_end',
        'reason': 'manual',
        'aborted': true,
        'errorMessage': 'Request aborted',
      });
      expect(c.reason, 'manual');
      expect(c.aborted, isTrue);
      expect(c.errorMessage, 'Request aborted');
      expect(c.summary, isEmpty);
      expect(c.failed, isTrue);
    });

    test('an older Pi that reports no estimatedTokensAfter still parses', () {
      final c = PiCompaction.fromEvent(
          _endFrame(summary: 'kept', estimatedTokensAfter: null));
      expect(c.tokensAfter, isNull);
      expect(c.failed, isFalse);
    });
  });

  group('copyableText', () {
    test('is the summary, not the header', () {
      expect(
        _compaction(_threshold(summary: 'What Pi kept.')).copyableText,
        'What Pi kept.',
      );
    });

    test('is the reason a stopped one gave', () {
      expect(
        _compaction(_threshold(summary: '', errorMessage: 'No response'))
            .copyableText,
        'No response',
      );
    });
  });

  group('the card wording', () {
    test('a compaction that worked says so, and why', () {
      expect(ChatBubble.compactionLabel(_threshold(summary: 'x')),
          'Context compacted');
      expect(ChatBubble.compactionReason('threshold'),
          'the conversation outgrew the model’s context window');
      expect(ChatBubble.compactionReason('manual'),
          'a /compact was asked for');
      expect(ChatBubble.compactionReason('overflow'),
          'a request exceeded the context window');
    });

    test('an unknown reason is shown as Pi named it', () {
      // A new reason in Pi is not a reason to show nothing.
      expect(ChatBubble.compactionReason('session_switch'), 'session_switch');
      expect(ChatBubble.compactionReason(''), '');
    });

    test('one that did not work says that instead', () {
      expect(
        ChatBubble.compactionLabel(_threshold(summary: '',
            errorMessage: '429 rate limited')),
        'Compaction failed',
      );
      expect(
        ChatBubble.compactionLabel(
            _threshold(summary: '', aborted: true, errorMessage: 'Stopped')),
        'Compaction stopped',
      );
    });

    test('the token figures are the context before and after', () {
      expect(ChatBubble.compactionTokens(195702, 32100), '196k → 32k');
      // A figure nobody measured is not invented.
      expect(ChatBubble.compactionTokens(195702, null), '196k replaced');
      expect(ChatBubble.compactionTokens(null, 32100), '');
    });
  });

  group('the view model', () {
    test('compaction_start puts a compacting activity on the busy line',
        () async {
      final service = FakePiService();
      final vm = PiViewModel(piService: service);

      service.emit({'type': 'agent_start'});
      service.emit({'type': 'turn_start'});
      service.emit({'type': 'compaction_start', 'reason': 'threshold'});
      await Future<void>.delayed(Duration.zero);

      expect(vm.progress.kind, ActivityKind.compacting);
      expect(vm.progress.activity, 'compacting context');

      vm.dispose();
      service._events.close();
    });

    test('compaction_end appends a line to the transcript at that point',
        () async {
      final service = FakePiService();
      final vm = PiViewModel(piService: service);

      service.emit({'type': 'agent_start'});
      service.emit({'type': 'turn_start'});
      service.emit({
        'type': 'message_end',
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'A very long answer.'}
          ],
        },
      });
      service.emit(_endFrame(summary: 'What Pi kept.'));
      service.emit({'type': 'turn_end'});
      service.emit({'type': 'agent_end', 'messages': []});
      await Future<void>.delayed(Duration.zero);

      final lines = vm.messages;
      expect(lines.last.role, 'system',
          reason: 'a compaction is not a turn, so it must not look like one');
      expect(lines.last.compaction, isNotNull);
      expect(lines.last.compaction!.summary, 'What Pi kept.');
      expect(lines.last.compaction!.tokensBefore, 195702);
      expect(lines.last.compaction!.tokensAfter, 32100);
      // The reply it followed is still the last thing Pi said.
      expect(lines[lines.length - 2].role, 'assistant');
      expect(lines[lines.length - 2].content, 'A very long answer.');

      vm.dispose();
      service._events.close();
    });

    test('a tool call after a compaction still belongs to the assistant',
        () async {
      // The reason the line is role 'system' and not 'assistant': a tool call is
      // appended to the last assistant message, and a compaction card is not one
      // it could belong to.
      final service = FakePiService();
      final vm = PiViewModel(piService: service);

      service.emit({'type': 'agent_start'});
      service.emit({'type': 'turn_start'});
      service.emit({
        'type': 'message_start',
        'message': {'role': 'assistant', 'content': <dynamic>[]},
      });
      service.emit(_endFrame(summary: 'What Pi kept.'));
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
        'type': 'tool_execution_end',
        'toolCallId': 'toolu_1',
        'toolName': 'bash',
        'result': {
          'content': [
            {'type': 'text', 'text': 'file1'}
          ],
        },
      });
      service.emit({'type': 'agent_end', 'messages': []});
      await Future<void>.delayed(Duration.zero);

      final withTool =
          vm.messages.where((m) => m.toolCalls.isNotEmpty).toList();
      expect(withTool, hasLength(1));
      expect(withTool.single.role, 'assistant');
      expect(vm.messages.where((m) => m.role == 'system'), hasLength(1),
          reason: 'the compaction line holds no tool call');
      expect(vm.messages.last.role, 'system');

      vm.dispose();
      service._events.close();
    });
  });

  group('the card', () {
    testWidgets('names what happened, why, and what it cost', (tester) async {
      await _pump(tester, _compaction(_threshold(summary: _summary(3))));

      expect(find.text('Context compacted'), findsOneWidget);
      expect(find.text('196k → 32k'), findsOneWidget);
      expect(
        find.text('the conversation outgrew the model’s context window'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.compress), findsOneWidget);
    });

    testWidgets('shows the summary it wrote', (tester) async {
      await _pump(tester, _compaction(_threshold(summary: _summary(3))));

      expect(find.textContaining('Paragraph 3 of the summary',
              findRichText: true),
          findsOneWidget);
      // Short enough that no fold is needed, so no control about one either.
      expect(find.textContaining('show the full summary'), findsNothing);
    });

    testWidgets('folds a long summary and says how much it folded',
        (tester) async {
      await _pump(tester, _compaction(_threshold(summary: _summary(13))));

      expect(find.textContaining('Paragraph 6 of the summary',
              findRichText: true),
          findsOneWidget);
      expect(find.textContaining('Paragraph 7 of the summary',
              findRichText: true),
          findsNothing);
      // How much is hidden, in the control before the tap.
      expect(find.text('show the full summary (7 more lines)'), findsOneWidget);

      await tester.tap(find.text('show the full summary (7 more lines)'));
      await tester.pump();

      expect(find.textContaining('Paragraph 13 of the summary',
              findRichText: true),
          findsOneWidget);
      expect(find.text('show the first 6 lines'), findsOneWidget);
    });

    testWidgets('a failed compaction is a line in the chat, not nothing',
        (tester) async {
      await _pump(
        tester,
        _compaction(_threshold(
            summary: '', errorMessage: '429 rate limited', aborted: true)),
      );

      expect(find.text('Compaction stopped'), findsOneWidget);
      expect(find.text('429 rate limited'), findsOneWidget);
      expect(find.text('Context compacted'), findsNothing);
    });

    testWidgets('the compact view keeps the fact and drops the document',
        (tester) async {
      await _pump(tester, _compaction(_threshold(summary: _summary(13))),
          compact: true);

      expect(find.text('Context compacted'), findsOneWidget);
      expect(find.text('196k → 32k'), findsOneWidget);
      expect(find.textContaining('Paragraph 1 of the summary',
              findRichText: true),
          findsNothing);
      expect(find.textContaining('show the full summary'), findsNothing);
    });
  });
}
