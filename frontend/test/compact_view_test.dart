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
import 'package:pi_mobile_agent/widgets/turn_status.dart';
import 'package:provider/provider.dart';

import 'support/app_menu.dart';

/// What a compact view is for: an agent run is mostly commands and their output,
/// and the same conversation should be readable either in full or as the short
/// version - *what Pi did, and to which files*.
const _path = 'frontend/lib/widgets/chat_bubble.dart';
const _otherPath = 'frontend/test/compact_view_test.dart';
const _old = 'final shell = isShellTool(tool.name);';
const _new = 'final shell = isShellTool(tool.name);\n    final compact = widget.compact;';
const _command = 'flutter build web 2>&1 | tail -4';
const _output = '✓ Built build/web\nTotal summarized in 1.2 seconds';
const _fileBody = 'import package flutter test here is the file content';
const _replyText = 'The build is green, so nothing needs changing.';

const _patchBody = '''*** Begin Patch
*** Update File: frontend/lib/widgets/chat_bubble.dart
@@
-old line
+new line
*** Add File: frontend/test/compact_view_test.dart
@@
+import 'package:flutter_test/flutter_test.dart';
*** End Patch''';

PiTool _edit({String? result}) => PiTool(
      name: 'edit',
      arguments: {
        'path': _path,
        'edits': [
          {'oldText': _old, 'newText': _new},
        ],
      },
      result: result ?? 'Successfully replaced 1 block(s).',
    );

PiTool _bash() =>
    PiTool(name: 'bash', arguments: {'command': _command}, result: _output);

PiTool _read() => PiTool(
      name: 'read',
      arguments: {'path': _path, 'offset': 1, 'limit': 40},
      result: _fileBody,
    );

PiTool _patch() =>
    PiTool(name: 'apply_patch', arguments: {'patch': _patchBody}, result: 'ok');

PiMessage _turn(List<PiTool> tools, {String content = _replyText}) => PiMessage(
      id: 'turn-1',
      role: 'assistant',
      content: content,
      timestamp: DateTime(2026),
      toolCalls: tools,
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
  // `Text.data` and `Text.textSpan` are both rendered text: a compact line is
  // one run with the name and the path as spans of it, so a helper that only
  // looked at `data` would report that the line is not on screen at all.
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((w) =>
          w.data ?? w.textSpan?.toPlainText() ?? '')
      .toList();
  final code = tester
      .widgetList<HighlightedCode>(find.byType(HighlightedCode))
      .map((w) => w.source)
      .toList();
  return [...texts, ...code].any((s) => s.contains(needle));
}

/// Stands in for a backend running tool calls, so the whole app can be asked
/// whether the menu's switch reaches the bubbles.
class _ToolService extends PiService {
  final StreamController<PiEvent> _events = StreamController<PiEvent>.broadcast();

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();
  @override
  Stream<PiEvent> get events => _events.stream;
  @override
  Future<List<PiModel>> getAvailableModels() async => const [];
  @override
  bool get isConnected => true;

  /// Pi's own first frame of a run. The busy line is the app saying a run is in
  /// flight, so a fixture that wants it has to say the same thing Pi does.
  void beginRun() =>
      _events.add(PiEvent(type: 'agent_start', data: const <String, dynamic>{}));

  void start(PiTool tool) {
    _events.add(PiEvent(type: 'tool_execution_start', data: {
      'toolCallId': 'call-${tool.name}',
      'toolName': tool.name,
      'args': tool.arguments,
    }));
  }

  void finish(PiTool tool, String result) {
    _events.add(PiEvent(type: 'tool_execution_end', data: {
      'toolCallId': 'call-${tool.name}',
      'toolName': tool.name,
      'result': result,
    }));
  }

  void run(PiTool tool, String result) {
    start(tool);
    finish(tool, result);
  }
}

void main() {
  group('which files a call names', () {
    test('an editing call names the file it changed', () {
      expect(ChatBubble.affectedFilesOf(_edit()), [_path]);
    });

    test('a read names the file it looked at', () {
      expect(ChatBubble.affectedFilesOf(_read()), [_path],
          reason: 'the compact view shows the type next to the path, so a read '
              'and an edit are not flattened into the same line - the list can '
              'say what the agent looked at as well as what it changed');
    });

    test('a patch names its files inside its own text', () {
      expect(ChatBubble.affectedFilesOf(_patch()), [_path, _otherPath],
          reason: 'apply_patch carries the patch and no path argument, so a '
              'view that only looked at arguments would report that nothing '
              'changed when something clearly did');
    });

    test('a file named twice is named once', () {
      expect(
        ChatBubble.affectedFilesOf(
            PiTool(name: 'edit', arguments: {'path': _path, 'file_path': _path})),
        [_path],
      );
    });
  });

  group('a bubble in each mode', () {
    testWidgets('compact mode shows the call and the file it names',
        (tester) async {
      await pumpBubble(tester, _turn([_edit()]), compact: true);

      expect(_shows(tester, 'edit  $_path'), isTrue,
          reason: 'the call type is what makes a path readable as an event - '
              'a list of paths alone cannot tell a read from an edit. On one '
              'line, because they are one fact');
      expect(_shows(tester, _new), isFalse,
          reason: 'the diff is the command half of the card, and the mode '
              'exists to hide it');
      expect(find.text('- oldText'), findsNothing);
      expect(find.text('+ newText'), findsNothing);
      expect(_shows(tester, 'Successfully replaced'), isFalse);
      expect(find.byType(HighlightedCode), findsNothing,
          reason: 'with no command, no diff and no output there is no code to '
              'draw. A card with nothing in it is a box around a path');
    });

    testWidgets('a command is named, and its command line is not shown',
        (tester) async {
      await pumpBubble(tester, _turn([_bash()]), compact: true);

      expect(_shows(tester, 'bash'), isTrue,
          reason: 'what a shell call changed is not knowable from its '
              'arguments, and the mode does not invent it - it says a command '
              'ran, which is what it can say');
      expect(_shows(tester, _command), isFalse);
      expect(_shows(tester, _output), isFalse);
    });

    testWidgets('a read says it read, and does not print the file',
        (tester) async {
      await pumpBubble(tester, _turn([_read()]), compact: true);

      expect(_shows(tester, 'read  $_path'), isTrue);
      expect(_shows(tester, _fileBody), isFalse,
          reason: 'the file is what the call read, which is its output. Naming '
              'the path is the fact the mode keeps; reciting it is not');
    });

    testWidgets('a patch is reported as the calls it was and the files it touched',
        (tester) async {
      await pumpBubble(tester, _turn([_patch()], content: ''), compact: true);

      expect(_shows(tester, 'apply_patch  $_path'), isTrue);
      expect(_shows(tester, _otherPath), isTrue,
          reason: 'the second file is a continuation line under the first, not '
              'a second call. A multi-file patch is one thing Pi did');
      expect(_shows(tester, '*** Begin Patch'), isFalse,
          reason: 'the patch is the argument. Reading the paths out of it is '
              'for saying which files it is about, not for printing it');
    });

    testWidgets("Pi's own text is not what the mode hides", (tester) async {
      await pumpBubble(tester, _turn([_edit(), _bash()]), compact: true);

      expect(_shows(tester, _replyText), isTrue,
          reason: 'the answer is the point of the conversation. A view that '
              'trimmed the replies would be a shorter conversation, not a '
              'shorter view of it');
    });

    testWidgets('full view shows the command, the output and the file',
        (tester) async {
      await pumpBubble(tester, _turn([_edit(), _bash()]), compact: false);

      expect(_shows(tester, _path), isTrue);
      expect(_shows(tester, _new), isTrue);
      expect(_shows(tester, _command), isTrue);
      expect(_shows(tester, _output), isTrue);
      expect(find.text('- oldText'), findsOneWidget);
      expect(find.text('output'), findsAtLeastNWidgets(1),
          reason: 'the label naming what came back. Two cards in one reply is '
              'two of them, which is why this does not count them');
    });
    testWidgets('a long path wraps inside the bubble rather than overflowing it',
        (tester) async {
      // The width a phone actually has, and an absolute path of the shape Pi
      // reports for a file outside the working directory - long enough that a
      // layout built out of two flex children would have had to truncate one of
      // them to fit the other.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final long =
          '/home/adam/source/repos/pi-mobile-agent/frontend/lib/widgets/chat_bubble.dart';
      await pumpBubble(
          tester,
          _turn([
            PiTool(name: 'edit', arguments: {'path': long}, result: 'ok'),
          ], content: ''),
          compact: true);

      expect(_shows(tester, long), isTrue,
          reason: 'the whole path is there. Truncating the one fact the mode '
              'keeps is not compact, it is missing');

      final bubble = tester.getRect(find.byType(ChatBubble));
      // The line itself, not the bubble's header: both are `Text`, and the
      // header is the one a bare `find.byType` reaches first.
      final line = find.byWidgetPredicate((w) =>
          w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').contains(long));
      final rect = tester.getRect(line);
      final size = tester.getSize(line);

      expect(size.height, greaterThanOrEqualTo(30),
          reason: 'the fixture is only worth anything if the path really is '
              'long enough to wrap - one line of 11.5px text is under 20');
      expect(rect.right, lessThanOrEqualTo(bubble.right + 0.5),
          reason: 'wrapped, inside the bubble - not overflowing it');
      expect(rect.left, greaterThanOrEqualTo(bubble.left - 0.5));
      expect(rect.bottom, lessThanOrEqualTo(bubble.bottom + 0.5));
    });
  });

  group('the rendered bubble and the mode it was rendered in', () {
    testWidgets('the cache cannot hand back the other mode\'s shape',
        (tester) async {
      final message = _turn([_edit(), _bash()]);

      // The same message, the same theme, the same size: only the view mode
      // changes. A body cache keyed without it hands back what it built before,
      // which is the failure this is here to catch - a setting that changes the
      // chat and then does not, because the chat was already built.
      await pumpBubble(tester, message, compact: false);
      expect(_shows(tester, _output), isTrue);

      await pumpBubble(tester, message, compact: true);
      expect(_shows(tester, _output), isFalse);
      expect(_shows(tester, 'edit  $_path'), isTrue,
          reason: 'and the other half of the swap has to arrive too, not just '
              'the half that left');

      await pumpBubble(tester, message, compact: false);
      expect(_shows(tester, _output), isTrue,
          reason: 'the same in the other direction - a compact body cached '
              'against a full view is the same bug wearing the other hat');
    });
  });

  group('the menu switch reaches the chat', () {
    Future<(_ToolService, PiViewModel)> pumpHome(WidgetTester tester) async {
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
      return (service, viewModel);
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

    testWidgets('the menu says which state it is in and what it costs',
        (tester) async {
      await pumpHome(tester);
      await openAppMenu(tester);

      // The row is below the fold of a test window, so it has to be scrolled to
      // before it exists to look at - the same as on a phone.
      await scrollMenuIntoView(tester, menuSwitch('Full view'));

      expect(find.text('Full view'), findsOneWidget);
      expect(
        find.text('Tool calls show the command and what it printed'),
        findsOneWidget,
      );

      await pressCompact(tester, 'Full view');
      expect(
        find.text('Tool calls show the call and any file it names - no '
            'commands, no output'),
        findsOneWidget,
        reason: 'the row has to read as the state it is now in. "Compact" is '
            'not a thing you can infer from the word',
      );
    });

    testWidgets('turning it on leaves the calls and the files, and drops the rest',
        (tester) async {
      final (service, _) = await pumpHome(tester);
      service.beginRun();
      service.run(_edit(), 'Successfully replaced 1 block(s).');
      service.run(_bash(), _output);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(_shows(tester, _output), isTrue,
          reason: 'the fixture is only worth anything if the output really is '
              'on screen before anything is pressed');
      expect(tester.widget<ChatList>(find.byType(ChatList)).compact, isFalse);

      await openAppMenu(tester);
      await pressCompact(tester, 'Full view');

      expect(_shows(tester, 'edit  $_path'), isTrue);
      expect(_shows(tester, _output), isFalse);
      expect(_shows(tester, _command), isFalse);
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

    testWidgets('the busy line keeps its kind and drops the words naming the run',
        (tester) async {
      final (service, _) = await pumpHome(tester);
      service.beginRun();
      // Started and not finished, which is the state the busy row exists for.
      service.start(_bash());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.descendant(
            of: find.byType(TurnStatusRow), matching: find.text('bash $_command')),
        findsOneWidget,
        reason: 'the live line is the app saying what it is doing, and its '
            'words are the call - which is what the mode hides',
      );

      await openAppMenu(tester);
      await pressCompact(tester, 'Full view');

      expect(find.byType(TurnStatusRow), findsOneWidget,
          reason: 'the row itself stays: a run in flight still has to say it '
              'is in flight. The chat carries the call types now, so this line '
              'only has to carry the kind, and its icon does');
      expect(
        find.descendant(
            of: find.byType(TurnStatusRow), matching: find.text('working')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byType(TurnStatusRow), matching: find.textContaining(_command)),
        findsNothing,
      );
    });
  });
}
