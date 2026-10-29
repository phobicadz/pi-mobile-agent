import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';
import 'package:pi_mobile_agent/widgets/chat_list.dart';
import 'package:provider/provider.dart';

/// A long single paragraph, so the reply is wide enough that its bubble really
/// does run into the width limit. A short reply is sized by its own text and
/// would look identical either way.
const _longReply =
    'this reply is deliberately wordy so that the bubble reaches the width the '
    'list allows it and stops growing there, which is the only case where a '
    'wider limit changes anything the user can actually see on screen at all';

/// Replays canned backend frames without a WebSocket, as chat_list_test does.
class _WideBubbleService extends PiService {
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

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));

  /// One finished assistant reply, so the chat holds a real bubble and no
  /// streaming indicator. The ids are what Pi sends, and widening is keyed on
  /// them - a fixture without them is not the fixture the app runs on.
  int _n = 0;

  void addAssistantReply(String text) {
    final id = 'reply-${++_n}';
    emit({
      'type': 'message_start',
      'message': {'id': id, 'role': 'assistant', 'content': []},
    });
    emit({
      'type': 'message_update',
      'assistantMessageEvent': {'type': 'text_delta', 'delta': text},
    });
    emit({
      'type': 'message_end',
      'message': {
        'id': id,
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': text}
        ]
      },
    });
    emit({'type': 'agent_end', 'messages': []});
  }
}

/// Pi's own replies, not the prompts - the prompts are the other bubbles in the
/// same list, and "the last bubble" would be whichever of the two came last.
Finder replies() => find.byWidgetPredicate(
    (widget) => widget is ChatBubble && widget.message.role == 'assistant');

/// The width of the bubble itself. Measuring the [ChatBubble] would always
/// report the whole row, because its root is an [Align] that fills the width it
/// is given; the box that actually gets wider is inside it.
double bubbleWidth(WidgetTester tester, [Finder? which]) => tester
    .getSize(find.descendant(
      of: which ?? replies().last,
      matching: find.byType(AnimatedContainer),
    ))
    .width;

/// Two taps inside the double-tap window. Any further apart and the gesture
/// arena sees two single taps - which is the failure mode this would otherwise
/// be silently testing instead of the one it claims to.
Future<void> doubleTap(WidgetTester tester, [Finder? which]) async {
  final target = which ?? replies().last;
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  Future<PiViewModel> pumpReply(WidgetTester tester,
      {double width = 800}) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _WideBubbleService();
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

    service.addAssistantReply(_longReply);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    return viewModel;
  }

  testWidgets('double-clicking a reply widens it to the full column',
      (tester) async {
    final viewModel = await pumpReply(tester);

    final normal = bubbleWidth(tester);
    // A tablet-sized window (600-900dp) gets the tablet measure: 700px.
    expect(normal, closeTo(700, 1),
        reason: 'the fixture must really be hitting the normal limit');

    await doubleTap(tester);

    // Widening means 95% of the window. The list's own 16px padding on each
    // side still bounds it, so 760 rather than 800.
    expect(bubbleWidth(tester), closeTo(760, 1),
        reason: 'the reply must fill the column, not just grow a little');

    viewModel.dispose();
  });

  testWidgets('double-clicking again puts it back', (tester) async {
    final viewModel = await pumpReply(tester);

    final normal = bubbleWidth(tester);
    await doubleTap(tester);
    expect(bubbleWidth(tester), greaterThan(normal));

    await doubleTap(tester);
    expect(bubbleWidth(tester), closeTo(normal, 1),
        reason: 'the second double-click is a toggle, not a one-way zoom');

    viewModel.dispose();
  });

  testWidgets('on a phone a reply takes the whole column without being asked',
      (tester) async {
    // 390 logical px: a phone. The list bounds a bubble at its own 16px of
    // padding on each side, so the column is 358 and that is what a reply gets.
    final viewModel = await pumpReply(tester, width: 390);

    expect(bubbleWidth(tester), closeTo(358, 1),
        reason: 'a narrow bubble with a fifth of the screen left over is not a '
            'design choice on a phone, it is the width nobody asked for');

    // The gesture is not offered there: there is nothing wider to go to.
    await doubleTap(tester);
    expect(bubbleWidth(tester), closeTo(358, 1),
        reason: 'a zoom that cannot zoom is a gesture with no meaning');

    viewModel.dispose();
  });

  testWidgets('a desktop window keeps the reading measure and the zoom',
      (tester) async {
    final viewModel = await pumpReply(tester, width: 1200);

    expect(bubbleWidth(tester), closeTo(800, 1),
        reason: 'on a desktop the measure is a fixed readable column, not the '
            'whole window');

    await doubleTap(tester);
    expect(bubbleWidth(tester), closeTo(1140, 1),
        reason: 'and widening into the rest of the window is still a choice');

    viewModel.dispose();
  });

  testWidgets('widening one reply leaves the others alone', (tester) async {
    final service = _WideBubbleService();
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

    service.addAssistantReply(_longReply);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    // A second exchange, so the list holds two replies of exactly the same kind.
    viewModel.setUserInput('a second prompt, with text long enough to make its '
        'own bubble run into the same width limit it is under');
    await viewModel.submitPrompt();
    service.addAssistantReply(_longReply);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(replies(), findsNWidgets(2));
    final first = bubbleWidth(tester, replies().first);

    await doubleTap(tester);

    expect(bubbleWidth(tester), greaterThan(first),
        reason: 'the reply that was clicked is the one that widened');
    expect(bubbleWidth(tester, replies().first), closeTo(first, 1),
        reason: 'the state is keyed per message, not global to the chat');

    viewModel.dispose();
  });
}
