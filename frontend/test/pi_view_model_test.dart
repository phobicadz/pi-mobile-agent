import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/models/turn_progress.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';

/// PiService stub that replays canned backend frames instead of a WebSocket.
class FakePiService extends PiService {
  final _events = StreamController<PiEvent>.broadcast();
  Stream<PiState> get stateUpdates => const Stream.empty();
  Stream<PiEvent> get events => _events.stream;

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));
}

/// PiService stub with canned directory browsing and cwd switching.
class FakeDirService extends FakePiService {
  String cwd;
  final Map<String, DirListing> dirs;
  String? lastSetPath;
  Future<String> Function(String path)? setWorkingDirectoryOverride;

  FakeDirService({required this.cwd, required this.dirs});

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<DirListing> listDirectory({String? path}) async =>
      dirs[path] ?? dirs[cwd]!;

  @override
  Future<String> setWorkingDirectory(String path) async {
    if (setWorkingDirectoryOverride != null) {
      return setWorkingDirectoryOverride!(path);
    }
    lastSetPath = path;
    cwd = path;
    return path;
  }
}

/// PiService stub whose resume command returns canned saved history, and whose
/// state afterwards is the directory the resumed session was recorded in - which
/// is what the backend reports after switch_session, because Pi rebuilds the
/// session there.
class FakeResumeService extends FakePiService {
  final List<Map<String, dynamic>> history;
  final String resumedCwd;
  final _states = StreamController<PiState>.broadcast();
  String? resumedPath;
  int stateRefreshes = 0;

  FakeResumeService(this.history, {this.resumedCwd = r'\Projects\resumed'});

  @override
  Stream<PiState> get stateUpdates => _states.stream;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<List<Map<String, dynamic>>> resumeSession(String sessionPath) async {
    resumedPath = sessionPath;
    return history;
  }

  @override
  Future<PiSessionStats> getSessionStats() async => PiSessionStats.fromJson({
        'tokens': {'input': 100, 'output': 20, 'total': 120},
        'cost': 0,
        // What Pi reports for whichever session is live now. A resumed
        // conversation is usually the long one, and its figures are the ones the
        // app has to show after the switch.
        'contextUsage': {
          'tokens': resumedPath == null ? 1200 : 148000,
          'contextWindow': 200000,
          'percent': resumedPath == null ? 0.6 : 74.0,
        },
      });

  @override
  Future<void> refreshState() async {
    stateRefreshes++;
    _states.add(PiState.fromJson({
      'cwd': resumedCwd,
      'cwdDisplay': '~/resumed',
    }));
  }
}

/// PiService stub for the "new session in this directory" command: it records
/// the call, keeps reporting the same working directory afterwards (which is
/// what the backend does - Pi starts a fresh conversation where it already
/// works), and can be made to fail like a backend rejection.
class FakeNewSessionService extends FakePiService {
  final String cwd;
  final _states = StreamController<PiState>.broadcast();
  int newSessionCalls = 0;
  bool failNewSession = false;

  FakeNewSessionService({this.cwd = r'\Projects\current'});

  @override
  Stream<PiState> get stateUpdates => _states.stream;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<void> newSession() async {
    newSessionCalls++;
    if (failNewSession) throw Exception('Pi client not initialized');
  }

  @override
  Future<void> refreshState() async {
    _states.add(PiState.fromJson({'cwd': cwd, 'cwdDisplay': '~'}));
  }
}

/// PiService stub that reports the backend's state on demand, the way the real
/// one does on connect and after a run settles.
class FakeStateService extends FakePiService {
  final _states = StreamController<PiState>.broadcast();

  @override
  Stream<PiState> get stateUpdates => _states.stream;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<void> sendPrompt(String message) async {}

  void report({required bool streaming}) => _states
      .add(PiState.fromJson({'isStreaming': streaming, 'cwd': r'C:\work'}));
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
    expect(vm.messages[1].toolCalls.length, 1,
        reason: 'tool call not duplicated');
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
    final text = tester.widget<Text>(find.text('Hello there, friend!'));
    expect(text.style!.color!.computeLuminance(), lessThan(0.2),
        reason: 'light theme text must be dark');
  });

  testWidgets('chat text is light in the dark theme', (tester) async {
    await pumpBubble(tester, ThemeMode.dark);
    final text = tester.widget<Text>(find.text('Hello there, friend!'));
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

  test('resuming a session follows the directory that session was recorded in',
      () async {
    final service = FakeResumeService(const []);
    final vm = PiViewModel(piService: service);

    // A settled run first, so there are per-session counters that must not
    // survive switching to a different session.
    service.emit({'type': 'agent_settled', 'aborted': false});
    await pumpEventQueue();
    expect(vm.sessionStats, isNotNull);

    await vm.resumeSession(r'\Projects\resumed\session.jsonl');
    await pumpEventQueue();

    expect(service.stateRefreshes, greaterThan(0),
        reason:
            'the app has to re-read the backend state after a session switch: '
            'the working directory is not something Pi reports in a chat event');
    expect(vm.workingDirectory, r'\Projects\resumed');
    expect(vm.workingDirectoryDisplay, '~/resumed');
    expect(vm.sessionStats?.contextTokens, 148000,
        reason:
            'the resumed conversation is the one whose context matters now; '
            'keeping the numbers of the session just left behind puts a figure '
            'in the app bar that describes a different conversation');

    vm.dispose();
  });

  test('startNewSession empties the chat and keeps the working directory',
      () async {
    const home = r'\Projects\current';
    final service = FakeNewSessionService(cwd: home);
    final vm = PiViewModel(piService: service);

    // The app bar learns the directory from the state stream, the same way it
    // does against the real backend.
    await service.refreshState();
    await pumpEventQueue();
    expect(vm.workingDirectory, home);

    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'hi'}
        ],
      },
    });
    await pumpEventQueue();
    expect(vm.messages, isNotEmpty);

    final ok = await vm.startNewSession();
    await pumpEventQueue();

    expect(ok, isTrue);
    expect(service.newSessionCalls, 1);
    expect(vm.messages, isEmpty, reason: 'a new chat starts empty');
    expect(vm.workingDirectory, home,
        reason: 'the new session stays in the directory being worked in');
    expect(vm.error, isNull);

    vm.dispose();
  });

  test('startNewSession reports a backend rejection and keeps the chat',
      () async {
    final service = FakeNewSessionService()..failNewSession = true;
    final vm = PiViewModel(piService: service);

    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'keep this'}
        ],
      },
    });
    await pumpEventQueue();

    final ok = await vm.startNewSession();
    await pumpEventQueue();

    expect(ok, isFalse);
    expect(vm.error, contains('new session'));
    expect(vm.messages, isNotEmpty,
        reason:
            'a failed command must not throw away the visible conversation');

    vm.dispose();
  });

  test('a run left in flight by a dropped socket is cleared by the next state',
      () async {
    final service = FakeStateService();
    final vm = PiViewModel(piService: service);

    await vm.submitPrompt('half a run');
    expect(vm.isLoading, isTrue);

    // The backend restarted mid-run: no agent_end is coming for this one, but
    // the app does get a state when it reconnects.
    service.report(streaming: false);
    await pumpEventQueue();

    expect(vm.isLoading, isFalse,
        reason:
            'otherwise the send, stop and new-session buttons stay disabled '
            'for the rest of the session');
    expect(vm.awaitingModel, isFalse);
    expect(vm.progress.active, isFalse);

    // A run that really is streaming is not cleared by it.
    await vm.submitPrompt('still going');
    service.report(streaming: true);
    await pumpEventQueue();
    expect(vm.isLoading, isTrue);

    service.report(streaming: false);
    await pumpEventQueue();
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

  test('DirListing parses the list_dir payload', () {
    final listing = DirListing.fromJson({
      'path': r'C:\Users\Chamb\source',
      'parent': r'C:\Users\Chamb',
      'roots': [
        {'name': 'C:', 'path': r'C:\'},
      ],
      'entries': [
        {'name': 'repos', 'path': r'C:\Users\Chamb\source\repos'},
      ],
      'current': r'C:\Users\Chamb\source\repos\pi-mobile-agent',
      'recent': [r'C:\Users\Chamb\source\repos'],
    });
    expect(listing.path, r'C:\Users\Chamb\source');
    expect(listing.parent, r'C:\Users\Chamb');
    expect(listing.roots.single.name, 'C:');
    expect(listing.entries.single.name, 'repos');
    expect(listing.current, r'C:\Users\Chamb\source\repos\pi-mobile-agent');
    expect(listing.recent, [r'C:\Users\Chamb\source\repos']);
  });

  test('browseDirectory exposes listing and current cwd', () async {
    const home = r'C:\home';
    final listing = DirListing(
      path: home,
      parent: r'C:\\',
      roots: [DirEntry(name: 'C:', path: r'C:\')],
      entries: [DirEntry(name: 'src', path: r'C:\home\src')],
      current: home,
      recent: const [r'C:\other'],
    );
    final service = FakeDirService(cwd: home, dirs: {home: listing});
    final vm = PiViewModel(piService: service);

    final result = await vm.browseDirectory();

    expect(result, isNotNull);
    expect(result!.path, home);
    expect(vm.workingDirectory, home);
    expect(vm.loadingDirectories, isFalse);

    vm.dispose();
  });

  test('setWorkingDirectory updates cwd and clears chat', () async {
    const home = r'C:\home';
    const target = r'C:\work';
    final listing = DirListing(
      path: home,
      parent: r'C:\\',
      roots: [DirEntry(name: 'C:', path: r'C:\')],
      entries: [DirEntry(name: 'work', path: target)],
      current: home,
      recent: const [],
    );
    final service = FakeDirService(cwd: home, dirs: {home: listing});
    final vm = PiViewModel(piService: service);

    // Seed a chat message so we can prove it gets cleared.
    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'hi'}
        ],
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(vm.messages.length, 1);

    final ok = await vm.setWorkingDirectory(target);

    expect(ok, isTrue);
    expect(service.lastSetPath, target);
    expect(vm.workingDirectory, target);
    expect(vm.messages, isEmpty, reason: 'Pi restarts with a fresh session');
    expect(vm.isLoading, isFalse);

    vm.dispose();
  });

  test('setWorkingDirectory reports failure and keeps state', () async {
    const home = r'C:\home';
    final listing = DirListing(
      path: home,
      parent: r'C:\\',
      roots: [DirEntry(name: 'C:', path: r'C:\')],
      entries: const [],
      current: home,
      recent: const [],
    );
    final service = FakeDirService(cwd: home, dirs: {home: listing});
    final vm = PiViewModel(piService: service);

    // Seed the known cwd the way the app does: by browsing.
    await vm.browseDirectory();
    expect(vm.workingDirectory, home);

    // Simulate a backend rejection (bad path).
    service.setWorkingDirectoryOverride =
        (String path) async => throw Exception('Not a directory: $path');

    final ok = await vm.setWorkingDirectory(r'C:\nope');

    expect(ok, isFalse);
    expect(vm.workingDirectory, home);
    expect(vm.error, contains('Not a directory'));

    vm.dispose();
  });

  test('streaming text is coalesced into a few rebuilds, not one per token',
      () async {
    final service = QuietPiService();
    final viewModel = PiViewModel(piService: service);
    var rebuilds = 0;
    viewModel.addListener(() => rebuilds++);
    final versionBefore = viewModel.messagesVersion;

    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    for (var i = 0; i < 200; i++) {
      service.emit({
        'type': 'message_update',
        'assistantMessageEvent': {'type': 'text_delta', 'delta': 'x'},
      });
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(viewModel.messages.single.content, hasLength(200),
        reason: 'no streamed text may be dropped');
    expect(viewModel.messagesVersion, greaterThan(versionBefore),
        reason: 'the chat list rebuilds when messages change');
    expect(rebuilds, lessThan(20),
        reason: '200 streamed tokens must not mean 200 widget rebuilds');

    viewModel.dispose();
  });

  test('typing a prompt does not notify or bump the chat version', () async {
    final service = QuietPiService();
    final viewModel = PiViewModel(piService: service);
    var rebuilds = 0;
    viewModel.addListener(() => rebuilds++);
    final versionBefore = viewModel.messagesVersion;

    // Typing used to notify here, which re-rendered the whole chat on every
    // keystroke. The TextField keeps its own text, so nothing needs to.
    viewModel.setUserInput('hello');

    expect(viewModel.messagesVersion, versionBefore);
    expect(rebuilds, 0);

    viewModel.dispose();
  });

  test('progress reports Pi usage and the tool it is running', () async {
    final service = QuietPiService();
    final viewModel = PiViewModel(piService: service);

    service.emit({'type': 'agent_start'});
    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    service.emit({
      'type': 'message_update',
      'usage': _usage(10, 4, 5870),
      'assistantMessageEvent': {'type': 'thinking_start', 'contentIndex': 0},
    });
    service.emit({
      'type': 'message_update',
      'usage': _usage(10, 4, 5870),
      'assistantMessageEvent': {
        'type': 'thinking_delta',
        'delta': 'I should read the file. ',
      },
    });

    // The fake service replays frames through a stream, so the view model has
    // to be given a turn to consume them.
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.progress.active, isTrue);
    expect(viewModel.progress.kind, ActivityKind.thinking);
    expect(viewModel.progress.activity, 'thinking',
        reason: 'reasoning must look like progress, not a frozen chat');
    expect(viewModel.progress.live.output, 4);

    service.emit({
      'type': 'tool_execution_start',
      'toolCallId': 'call_1',
      'toolName': 'read',
      'args': {'path': r'C:\Users\chamb\app\src\index.ts'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.progress.kind, ActivityKind.reading);
    expect(viewModel.progress.activity, 'read index.ts');

    service.emit({
      'type': 'tool_execution_update',
      'toolCallId': 'call_1',
      'toolName': 'read',
      'args': const {},
      'partialResult': {
        'content': [
          {'type': 'text', 'text': 'a' * 1200}
        ]
      },
    });
    service.emit({
      'type': 'tool_execution_update',
      'toolCallId': 'call_1',
      'toolName': 'read',
      'args': const {},
      // A tool may replace its partial result instead of extending it: only the
      // growth counts, so a replaced result is not double-counted.
      'partialResult': {
        'content': [
          {'type': 'text', 'text': 'a' * 1000}
        ]
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.progress.toolOutputChars, 1200,
        reason:
            'a shorter replacement partial result must not shrink the count');

    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'done'}
        ],
        'usage': _usage(10, 224, 5870, reasoning: 168, cost: 0.0085),
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.progress.completed.output, 224);

    service.emit({
      'type': 'message_end',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'index.ts'}
        ],
        'usage': _usage(13, 45, 6394, cost: 0.0015),
      },
    });
    await Future<void>.delayed(Duration.zero);

    // Both responses of the run add up: Pi answers once per tool round.
    expect(viewModel.progress.completed.output, 269);
    expect(viewModel.progress.producedTokens, 269);
    expect(viewModel.progress.live, PiUsage.zero);

    service.emit({'type': 'agent_end'});
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.progress.active, isFalse,
        reason: 'the progress line is gone once the run finishes');
    expect(viewModel.messages.last.usage?.output, 45,
        reason: 'a finished reply shows what it cost');

    viewModel.dispose();
  });

  test(
      'progress estimates tokens when the provider reports none while streaming',
      () async {
    final service = QuietPiService();
    final viewModel = PiViewModel(piService: service);

    service.emit({'type': 'agent_start'});
    service.emit({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object>[]},
    });
    // Providers that only report usage at completion send zeros throughout.
    for (var i = 0; i < 20; i++) {
      service.emit({
        'type': 'message_update',
        'usage': _usage(0, 0, 0),
        'assistantMessageEvent': {'type': 'thinking_delta', 'delta': 'x' * 20},
      });
    }

    await Future<void>.delayed(Duration.zero);

    expect(viewModel.progress.live.isEmpty, isTrue);
    expect(viewModel.progress.estimated, isTrue);
    expect(viewModel.progress.estimatedTokens, 100,
        reason:
            '20 thinking deltas of 20 characters, at ~4 characters per token');
    expect(viewModel.progress.producedTokens, 100,
        reason: 'the estimate is what makes the counter move at all');

    service.emit({'type': 'agent_end'});
    viewModel.dispose();
  });

  test('PiSessionStats parses the get_session_stats payload', () {
    final stats = PiSessionStats.fromJson({
      'tokens': {
        'input': 50000,
        'output': 10000,
        'cacheRead': 40000,
        'cacheWrite': 5000,
        'total': 105000,
      },
      'cost': 0.45,
      'contextUsage': {'tokens': 60000, 'contextWindow': 200000, 'percent': 30},
    });

    expect(stats.tokens.output, 10000);
    expect(stats.tokens.totalTokens, 105000,
        reason:
            'session totals use "total" where a response usage uses "totalTokens"');
    expect(stats.cost, closeTo(0.45, 0.0001));
    expect(stats.contextTokens, 60000);
    expect(stats.contextPercent, 30);

    // Right after compaction Pi omits the context usage.
    final withoutContext = PiSessionStats.fromJson({
      'tokens': {'output': 1},
      'cost': 0
    });
    expect(withoutContext.contextTokens, isNull);
  });

  test(
    'a model that refuses to answer leaves its reason in the chat, not silence',
    () async {
      final service = QuietPiService();
      final vm = PiViewModel(piService: service);

      // Captured from the live backend with a model the Copilot account does
      // not have: the assistant message exists, has no text, and says why.
      service.emit({'type': 'agent_start'});
      service.emit({
        'type': 'message_start',
        'message': {'role': 'assistant', 'content': <dynamic>[]},
      });
      service.emit({
        'type': 'message_end',
        'message': {
          'role': 'assistant',
          'content': <dynamic>[],
          'stopReason': 'error',
          'errorMessage':
              'github-copilot API error (400): The requested model is not '
                  'available for integrator "vscode-chat".',
        },
      });
      service.emit({'type': 'agent_end', 'messages': []});

      await Future<void>.delayed(Duration.zero);

      expect(vm.messages.length, 1,
          reason: 'the failed reply must not be dropped');
      expect(vm.messages.single.errorMessage, contains('not available'));
      expect(vm.messages.single.stopReason, 'error');
      // A run that failed is a finished run: nothing may stay disabled waiting
      // for a reply that is never coming.
      expect(vm.isLoading, isFalse);

      vm.dispose();
    },
  );

  testWidgets('the reason a provider gave is readable in the chat',
      (tester) async {
    final message = PiMessage(
      id: 'assistant-1',
      role: 'assistant',
      content: '',
      timestamp: DateTime(2026),
      stopReason: 'error',
      errorMessage: 'github-copilot API error (400): model_not_available',
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [ChatBubble(message: message)])),
    ));

    expect(find.textContaining('model_not_available'), findsOneWidget);
    // An empty reply with no error still renders nothing at all.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          ChatBubble(
              message: PiMessage(
            id: 'assistant-2',
            role: 'assistant',
            content: '',
            timestamp: DateTime(2026),
          )),
        ]),
      ),
    ));
    expect(find.textContaining('model_not_available'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a run that ends without answering says so instead of leaving silence',
      () async {
    final service = QuietPiService();
    final vm = PiViewModel(piService: service);

    // Captured from the live backend: the model was asked something it chose to
    // end on without producing text, so the run has an assistant message with
    // no content and no reason attached to it.
    service.emit({'type': 'agent_start'});
    service.emit({'type': 'turn_start'});
    service.emit({
      'type': 'agent_end',
      'messages': [
        {
          'role': 'assistant',
          'content': <dynamic>[],
          'stopReason': 'stop',
        },
      ],
    });

    await Future<void>.delayed(Duration.zero);

    expect(vm.messages.length, 1,
        reason: 'a run with nothing to show still has to appear in the chat');
    expect(vm.messages.single.localNote, isTrue,
        reason: 'the app wrote this line, so it must not read as a reply');
    expect(vm.messages.single.content, contains('no reply'));
    expect(vm.isLoading, isFalse);

    vm.dispose();
  });

  test(
    'a run the user stopped is not reported as having said nothing',
    () async {
      final service = QuietPiService();
      final vm = PiViewModel(piService: service);

      service.emit({'type': 'agent_start'});
      service.emit({
        'type': 'agent_end',
        'messages': [
          {
            'role': 'assistant',
            'content': <dynamic>[],
            'stopReason': 'aborted',
          },
        ],
      });

      await Future<void>.delayed(Duration.zero);

      expect(vm.messages, isEmpty,
          reason: 'the partial reply and the stopped state already say this');

      vm.dispose();
    },
  );

  test(
    'a run that only ran tools is not treated as having said nothing',
    () async {
      final service = QuietPiService();
      final vm = PiViewModel(piService: service);

      service.emit({'type': 'agent_start'});
      service.emit({
        'type': 'agent_end',
        'messages': [
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'toolCall',
                'id': 'call-1',
                'name': 'bash',
                'arguments': {}
              },
            ],
            'stopReason': 'toolUse',
          },
        ],
      });

      await Future<void>.delayed(Duration.zero);

      expect(vm.messages.any((m) => m.localNote), isFalse,
          reason: 'running commands is an answer of its own');

      vm.dispose();
    },
  );

  testWidgets('a no-reply note renders as a status line, not a reply bubble',
      (tester) async {
    final note = PiMessage(
      id: 'no-reply-1',
      role: 'assistant',
      content: 'Pi finished with no reply.',
      timestamp: DateTime(2026),
      localNote: true,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [ChatBubble(message: note)])),
    ));

    expect(find.textContaining('Pi finished with no reply'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _usage(int input, int output, int cacheRead,
        {int reasoning = 0, double cost = 0}) =>
    {
      'input': input,
      'output': output,
      'cacheRead': cacheRead,
      'cacheWrite': 0,
      'totalTokens': input + output + cacheRead,
      'reasoning': reasoning,
      'cost': {'total': cost},
    };

/// FakePiService that never touches the network for the model list.
class QuietPiService extends FakePiService {
  @override
  Future<List<PiModel>> getAvailableModels() async => const [];
}
