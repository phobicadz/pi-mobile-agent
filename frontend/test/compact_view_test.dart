import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/utils/code_highlight.dart';
import 'package:pi_mobile_agent/utils/dracula_scheme.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';
import 'package:pi_mobile_agent/widgets/chat_list.dart';
import 'package:provider/provider.dart';

import 'support/app_menu.dart';

/// What a compact view is for: an agent run is mostly tool *output*, and the
/// same conversation should be readable either as a transcript of the commands
/// or as a record of what they said. These tests are the difference between
/// those two, and the parts that must not change.
const _command = 'flutter build web 2>&1 | tail -4';
const _output = '✓ Built build/web\nTotal summarized in 1.2 seconds';
const _replyText = 'The build is green, so nothing needs changing.';

PiMessage _turn({bool withText = true, String? result = _output}) => PiMessage(
      id: 'turn-1',
      role: 'assistant',
      content: withText ? _replyText : '',
      timestamp: DateTime(2026),
      toolCalls: [
        PiTool(name: 'bash', arguments: {'command': _command}, result: result),
      ],
    );

/// A bubble on its own, in the mode under test.
Future<void> pumpBubble(WidgetTester tester, PiMessage message,
    {required bool compact}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: Dracula.darkScheme(),
      brightness: Brightness.dark,
    ),
    home: Scaffold(
      body: ListView(
        children: [ChatBubble(message: message, compact: compact)],
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 120));
}

/// Whether a string is drawn anywhere in what is on screen - as a `Text`, or as
/// the source of a highlighted block. A tool result is one or the other
/// depending on whether it looks like code, and a test that only looks for one
/// passes over the case it is not looking at.
bool _shows(WidgetTester tester, String needle) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .toList();
  final code = tester
      .widgetList<HighlightedCode>(find.byType(HighlightedCode))
      .map((w) => w.source)
      .toList();
  return [...texts, ...code].any((s) => s.contains(needle));
}

/// Stands in for a backend running one tool call, so the whole app can be asked
/// whether the menu's switch reaches the bubbles.
class _ToolService extends PiService {
  final StreamController<PiEvent> _events =
      StreamController<PiEvent>.broadcast();

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();
  @override
  Stream<PiEvent> get events => _events.stream;
  @override
  Future<List<PiModel>> getAvailableModels() async => const [];
  @override
  bool get isConnected => true;

  void runTool() {
    _events.add(PiEvent(type: 'tool_execution_start', data: {
      'toolCallId': 'call-1',
      'toolName': 'bash',
      'args': {'command': _command},
    }));
    _events.add(PiEvent(type: 'tool_execution_end', data: {
      'toolCallId': 'call-1',
      'toolName': 'bash',
      'result': _output,
    }));
  }
}

void main() {
  group('a bubble in each mode', () {
    testWidgets('compact mode keeps the command and drops what it printed',
        (tester) async {
      await pumpBubble(tester, _turn(), compact: true);

      expect(_shows(tester, _command), isTrue,
          reason: 'the command is what the agent ran, which is the half a '
              'compact view exists to show');
      expect(find.text('command'), findsOneWidget,
          reason: 'the parameter label stays too - a command with no saying '
              'what it is a parameter of is just text again');
      expect(_shows(tester, _output), isFalse,
          reason: 'the output is most of the height of an agent run, and it '
              'is the half this mode is about');
      expect(find.text('output'), findsNothing,
          reason: 'the label belongs to a block that is not there. A label for '
              'nothing is a heading over an empty space');
    });

    testWidgets('full mode shows both halves, as it always did',
        (tester) async {
      await pumpBubble(tester, _turn(), compact: false);

      expect(_shows(tester, _command), isTrue);
      expect(_shows(tester, _output), isTrue);
      expect(find.text('output'), findsOneWidget);
    });

    testWidgets('Pi\'s own text is not what compact mode hides',
        (tester) async {
      await pumpBubble(tester, _turn(), compact: true);

      expect(_shows(tester, _replyText), isTrue,
          reason: 'the answer is the point of the conversation. A compact view '
              'that trimmed the replies would be a shorter conversation, not a '
              'shorter view of it');
    });

    testWidgets('an edit keeps its diff, because a diff is what it ran',
        (tester) async {
      final message = PiMessage(
        id: 'edit-1',
        role: 'assistant',
        content: '',
        timestamp: DateTime(2026),
        toolCalls: [
          PiTool(
            name: 'edit',
            arguments: {
              'path': 'frontend/lib/widgets/chat_bubble.dart',
              'edits': [
                {
                  'oldText': 'final shell = isShellTool(tool.name);',
                  'newText':
                      'final shell = isShellTool(tool.name);\n    final compact = widget.compact;',
                },
              ],
            },
            result: 'Successfully replaced 1 block(s).',
          ),
        ],
      );
      await pumpBubble(tester, message, compact: true);

      expect(find.text('- oldText'), findsOneWidget);
      expect(find.text('+ newText'), findsOneWidget);
      expect(
        tester.widgetList<HighlightedCode>(find.byType(HighlightedCode)).length,
        2,
        reason: 'what an edit changed is the work, not the noise about it - '
            'a card that shows only a path says nothing about the change',
      );

      // The status line *is* output, so it goes with the rest of the output.
      expect(_shows(tester, 'Successfully replaced'), isFalse);
    });

    testWidgets('a tool call with no arguments still says what it was',
        (tester) async {
      final message = PiMessage(
        id: 'no-args',
        role: 'assistant',
        content: '',
        timestamp: DateTime(2026),
        toolCalls: [PiTool(name: 'bash', arguments: {}, result: _output)],
      );
      await pumpBubble(tester, message, compact: true);

      expect(find.text('bash'), findsOneWidget,
          reason: 'with nothing to run and nothing printed, the card is the '
              'name of the call. That is still the command, and hiding the '
              'whole card would hide the fact that anything happened at all');
    });
  });

  group('the rendered bubble and the mode it was rendered in', () {
    testWidgets('the cache cannot hand back the other mode\'s shape',
        (tester) async {
      final message = _turn();

      // The same message, the same theme, the same size: only the view mode
      // changes. A body cache keyed without it hands back what it built before,
      // which is the failure this is here to catch - a setting that changes the
      // chat and then does not, because the chat was already built.
      await pumpBubble(tester, message, compact: false);
      expect(_shows(tester, _output), isTrue);

      await pumpBubble(tester, message, compact: true);
      expect(_shows(tester, _output), isFalse,
          reason: 'the cached full-mode body is still in the tree otherwise');

      await pumpBubble(tester, message, compact: false);
      expect(_shows(tester, _output), isTrue,
          reason: 'the same in the other direction - a compact body cached '
              'against a full view is the same bug wearing the other hat');
    });
  });

  group('the menu switch reaches the chat', () {
    Future<AppearanceController> pumpHome(WidgetTester tester) async {
      final service = _ToolService();
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
      service.runTool();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return appearance;
    }

    /// Press the switch. The menu is left open by the caller, because that is
    /// what the app does with its settings - they are pressed and their effect
    /// watched without closing the menu - and tapping the app bar's menu button
    /// again while the drawer is open is a tap on the drawer.
    Future<void> pressCompact(WidgetTester tester, String title) async {
      final target = menuSwitch(title);
      await scrollMenuIntoView(tester, target);
      await tester.tap(target);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('the menu offers it as a named pair of states, not a mystery',
        (tester) async {
      await pumpHome(tester);
      await openAppMenu(tester);

      // The row is below the fold of a test window, so it has to be scrolled to
      // before it exists to look at - the same as on a phone.
      await scrollMenuIntoView(tester, menuSwitch('Full view'));

      // It says which state it is in and what turning it costs, because
      // "compact" is not a thing you can infer from the word.
      expect(find.text('Full view'), findsOneWidget);
      expect(
        find.text('Tool calls show the command and what it printed'),
        findsOneWidget,
      );
    });

    testWidgets('turning it on hides the output in the chat itself',
        (tester) async {
      await pumpHome(tester);

      expect(_shows(tester, _output), isTrue,
          reason: 'the fixture is only worth anything if the tool output really '
              'is on screen before anything is pressed');
      expect(tester.widget<ChatList>(find.byType(ChatList)).compact, isFalse);

      await openAppMenu(tester);
      await pressCompact(tester, 'Full view');

      expect(_shows(tester, _command), isTrue,
          reason: 'the command stays in the chat, not just in the bubble test');
      expect(_shows(tester, _output), isFalse);
      expect(tester.widget<ChatList>(find.byType(ChatList)).compact, isTrue,
          reason: 'the mode has to reach the list that builds the bubbles - a '
              'bubble reading the setting itself would not be part of its cache '
              'key, which is the whole reason the size is passed down too');

      // And back again, in the same session, without a reload. The menu is
      // still open, which is what it does while a setting is being watched.
      await pressCompact(tester, 'Compact view');
      expect(_shows(tester, _output), isTrue);
      expect(tester.widget<ChatList>(find.byType(ChatList)).compact, isFalse);
    });
  });
}
