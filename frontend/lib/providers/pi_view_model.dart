import 'dart:async';

import 'package:flutter/material.dart';
import '../services/pi_service.dart';
import '../models/pi_models.dart';
import '../models/turn_progress.dart';

class PiViewModel extends ChangeNotifier {
  final PiService piService;

  PiState? _state;
  final List<PiMessage> _messages = [];
  List<PiModel> _availableModels = [];
  List<PiSessionInfo> _sessions = [];
  String? _workingDirectory;
  String? _workingDirectoryDisplay;
  bool _loadingDirectories = false;
  bool _isLoading = false;
  bool _loadingSessions = false;
  String? _error;
  String _userInput = '';

  /// The assistant reply currently being streamed, if any.
  PiMessage? _streamingMessage;

  /// A turn is running but Pi has put nothing on screen yet (no assistant
  /// message has started). The chat shows a "thinking" bubble for exactly this
  /// window, which is otherwise an unresponsive-looking chat.
  bool _awaitingModel = false;

  // --- live progress for the current run ---------------------------------
  //
  // Pi reports token usage in two places: on every `message_update` frame
  // (`usage`, cumulative for the response being streamed) and on the finished
  // assistant message (`message.usage`). A run answers once per tool round, so
  // the per-response numbers are summed for the run total.

  /// Usage of the assistant response currently streaming.
  PiUsage _liveUsage = PiUsage.zero;

  /// Usage of the responses already completed in this run.
  PiUsage _runUsage = PiUsage.zero;

  /// Characters streamed for the response in flight. Providers that report
  /// usage only at completion would otherwise show nothing while working.
  int _responseChars = 0;

  /// Characters of tool output produced in this run - how far a file read or a
  /// long command has got - which is the progress the user asked to see when Pi
  /// is reading or writing a file.
  int _toolOutputChars = 0;
  final Map<String, int> _toolOutputByCall = {};

  /// Status-line label and icon per tool call, so a `tool_execution_update`
  /// that omits the arguments does not downgrade `read index.ts` to `read`.
  final Map<String, (String, ActivityKind)> _toolLabels = {};

  /// What the status line shows: the icon kind and its label.
  ActivityKind _activityKind = ActivityKind.idle;
  String _activity = '';

  PiSessionStats? _sessionStats;

  /// Bumped whenever the rendered message list changes. The chat list listens
  /// to this instead of the whole view model, so unrelated updates (state
  /// polling, session browsing) cannot make it rebuild.
  int _messagesVersion = 0;

  bool _disposed = false;
  bool _notifyScheduled = false;
  DateTime _lastNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Pi streams text token by token. Re-rendering the chat for every token is
  /// what makes streaming look janky, so updates are coalesced to this
  /// interval; the visible result is the same, at a fraction of the work.
  static const Duration _streamNotifyInterval = Duration(milliseconds: 60);

  PiViewModel({required this.piService}) {
    _initialize();
  }

  // Getters
  PiState? get state => _state;
  List<PiMessage> get messages => _messages;
  List<PiModel> get availableModels => _availableModels;
  List<PiSessionInfo> get sessions => _sessions;
  String? get workingDirectory => _workingDirectory;

  /// Same directory, shortened to "~" / "~/..." for the app bar.
  String? get workingDirectoryDisplay =>
      _workingDirectoryDisplay ?? _workingDirectory;
  bool get loadingDirectories => _loadingDirectories;
  bool get loadingSessions => _loadingSessions;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get userInput => _userInput;
  int get messagesVersion => _messagesVersion;
  bool get awaitingModel => _awaitingModel;

  /// Live view of the run in flight, shown in the streaming chat bubble.
  TurnProgress get progress {
    final waiting = _activity.isEmpty && _awaitingModel;
    return TurnProgress(
      active: _isLoading,
      kind: waiting ? ActivityKind.waiting : _activityKind,
      activity: _activity.isNotEmpty
          ? _activity
          : (waiting ? 'waiting for model' : ''),
      completed: _runUsage,
      live: _liveUsage,
      estimatedTokens: _responseChars ~/ 4,
      toolOutputChars: _toolOutputChars,
      contextTokens: _sessionStats?.contextTokens,
      contextWindow: _sessionStats?.contextWindow,
      contextPercent: _sessionStats?.contextPercent,
    );
  }

  PiSessionStats? get sessionStats => _sessionStats;
  bool get isConnected => piService.isConnected;

  void _initialize() {
    // Subscribe to Pi service events
    piService.events.listen(_handleEvent);

    piService.stateUpdates.listen((state) {
      _state = state;
      // The backend reports Pi's working directory in every state update, so the
      // app bar shows the real directory from the first connect instead of a
      // placeholder until something has been browsed.
      if (state.cwd != null && state.cwd!.isNotEmpty) {
        _workingDirectory = state.cwd;
        _workingDirectoryDisplay = state.cwdDisplay ?? state.cwd;
      }
      // Pi's state is the only thing that can say whether a run is still in
      // flight after the socket dropped mid-run - a backend restart, a phone
      // sleeping, a walk out of wifi range. The agent_end that would have
      // cleared it never arrives, and without this the send, stop and new-session
      // buttons stay disabled for the rest of the session.
      if (!state.isProcessing && _isLoading) {
        _isLoading = false;
        _awaitingModel = false;
        _streamingMessage?.streaming = false;
        _streamingMessage = null;
        _bumpMessages();
        _setActivity(ActivityKind.idle, '');
      }
      // The first state fetch can beat the initial model load (the socket may
      // not be open yet), so retry once we know the backend is reachable.
      if (_availableModels.isEmpty) {
        unawaited(_loadModels());
      }
      _notifyNow();
    });

    // Load initial data
    _loadModels();
  }

  /// Keeps the prompt in the model so it can be submitted from anywhere. The
  /// text itself is rendered by the app's own TextField, so this deliberately
  /// does not notify: notifying here rebuilt the whole chat on every keystroke.
  void setUserInput(String input) {
    _userInput = input;
  }

  void _notifyNow() {
    if (_disposed) return;
    _lastNotifyAt = DateTime.now();
    notifyListeners();
  }

  /// Coalesces Pi's high-frequency events into one rebuild per interval.
  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    final wait =
        _streamNotifyInterval - DateTime.now().difference(_lastNotifyAt);
    Future<void>.delayed(wait < Duration.zero ? Duration.zero : wait, () {
      _notifyScheduled = false;
      if (_disposed) return;
      _lastNotifyAt = DateTime.now();
      notifyListeners();
    });
  }

  void _bumpMessages() => _messagesVersion++;

  Future<void> _loadModels() async {
    try {
      _availableModels = await piService.getAvailableModels();
      _notifyNow();
    } catch (e) {
      _error = 'Failed to load models: $e';
      _notifyNow();
    }
  }

  void _handleEvent(PiEvent event) {
    final data = event.data;

    switch (event.type) {
      case 'agent_start':
        _resetRunCounters();
        _isLoading = true;
        break;

      case 'turn_start':
        _awaitingModel = true;
        _setActivity(ActivityKind.waiting, 'waiting for model');
        break;

      case 'message_start':
        final message = data['message'];
        if (message is Map<String, dynamic>) {
          if (message['role'] == 'assistant') {
            _awaitingModel = false;
            // Each assistant response starts a fresh usage count; the run total
            // is kept separately in [_runUsage].
            _liveUsage = PiUsage.zero;
            _responseChars = 0;
            _setActivity(ActivityKind.thinking, 'thinking');
          }
          _addMessage(PiMessage.fromJson(message),
              streaming: message['role'] == 'assistant');
        }
        break;

      case 'message_update':
        _handleMessageUpdate(data);
        break;

      case 'message_end':
        final message = data['message'];
        if (message is Map<String, dynamic>) {
          // The completed message is the authoritative source of its usage, and
          // of why it ended: a provider that refused the request says so here,
          // and that reason is the only content the response has.
          final parsed = PiMessage.fromJson(message);
          final usage = parsed.usage ?? PiUsage.zero;
          if (!usage.isEmpty) {
            _runUsage = _runUsage + usage;
            _liveUsage = PiUsage.zero;
            _responseChars = 0;
          }
          final text = _textOf(message);
          if (_streamingMessage != null) {
            if (text.isNotEmpty) _streamingMessage!.content = text;
            // The bubble Pi just finished writing carries its own usage, so the
            // reply shows what it cost.
            if (!usage.isEmpty) _streamingMessage!.usage = usage;
            _streamingMessage!.stopReason = parsed.stopReason;
            _streamingMessage!.errorMessage = parsed.errorMessage;
            _streamingMessage!.streaming = false;
            _streamingMessage = null;
            // The bubble Pi finished writing must stop showing the live status
            // line, so the chat list has to rebuild it.
            _bumpMessages();
          } else {
            if (parsed.content.isNotEmpty ||
                parsed.toolCalls.isNotEmpty ||
                parsed.errorMessage != null) {
              _addMessage(parsed);
            }
          }
        }
        break;

      case 'tool_execution_start':
        final args = _argsOf(data['args']);
        final toolId = data['toolCallId'] as String? ?? '';
        final toolName = data['toolName'] as String? ?? 'tool';
        final label = _describeTool(toolName, args);
        final kind = _kindForTool(toolName);
        _toolLabels[toolId] = (label, kind);
        _setActivity(kind, label);
        _appendTool(PiTool(
          id: toolId,
          name: data['toolName'] as String? ?? 'tool',
          arguments: args,
        ));
        break;

      case 'tool_execution_update':
        _trackToolOutput(
          data['toolCallId'] as String?,
          data['partialResult'],
          data['toolName'] as String?,
          _argsOf(data['args']),
        );
        break;

      case 'tool_execution_end':
        _trackToolOutput(
          data['toolCallId'] as String?,
          data['result'],
          null,
          const {},
        );
        _finishTool(
          data['toolCallId'] as String?,
          _resultText(data['result']),
        );
        break;

      case 'agent_end':
        _streamingMessage?.streaming = false; // never leave a spinner spinning
        _streamingMessage = null;
        _bumpMessages();
        _awaitingModel = false;
        _isLoading = false;
        _liveUsage = PiUsage.zero; // already counted into [_runUsage]
        _setActivity(ActivityKind.idle, '');
        break;

      case 'agent_settled':
        // Pi has no more automatic work: pull the session totals so the next
        // run can show real context usage instead of only this run's numbers.
        _awaitingModel = false;
        _isLoading = false;
        _setActivity(ActivityKind.idle, '');
        unawaited(_refreshSessionStats());
        break;

      default:
        // Other lifecycle events (turn_end/...) are not rendered as chat
        // bubbles.
        return;
    }

    _scheduleNotify();
  }

  void _handleMessageUpdate(Map<String, dynamic> data) {
    // Pi attaches the latest cumulative usage of the response being streamed to
    // every frame. It can stay zero until completion, so the character count is
    // kept as a fallback estimate.
    final usage = PiUsage.fromJson(data['usage']);
    if (!usage.isEmpty) _liveUsage = usage;

    final inner = data['assistantMessageEvent'];
    if (inner is! Map<String, dynamic>) return;

    switch (inner['type']) {
      case 'thinking_start':
        _setActivity(ActivityKind.thinking, 'thinking');
        break;

      case 'thinking_delta':
        final delta = inner['delta'] as String? ?? '';
        if (delta.isEmpty) return;
        // Thinking is not rendered as a bubble, but counting it is what makes
        // "Pi is working" visible while it reasons.
        _responseChars += delta.length;
        _setActivity(ActivityKind.thinking, 'thinking');
        break;

      case 'text_start':
        _setActivity(ActivityKind.writing, 'writing');
        break;

      case 'text_delta':
        final delta = inner['delta'] as String? ?? '';
        if (delta.isEmpty) return;
        _responseChars += delta.length;
        _setActivity(ActivityKind.writing, 'writing');
        _ensureStreamingMessage().content += delta;
        _bumpMessages();
        break;

      case 'toolcall_start':
        final toolName = inner['toolName'] as String? ?? 'tool';
        _setActivity(_kindForTool(toolName), 'calling $toolName');
        break;

      case 'toolcall_delta':
        _responseChars += (inner['delta'] as String? ?? '').length;
        break;

      case 'toolcall_end':
        final call = inner['toolCall'];
        if (call is Map<String, dynamic>) {
          _appendTool(PiTool(
            id: call['id'] as String? ?? '',
            name: call['name'] as String? ?? 'tool',
            arguments: _argsOf(call['arguments']),
          ));
        }
        break;
    }
  }

  /// Tool arguments, tolerant of any map the frame carries (`const {}`, a
  /// decoded JSON object, or none at all) instead of assuming one exact type.
  static Map<String, dynamic> _argsOf(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  void _resetRunCounters() {
    _liveUsage = PiUsage.zero;
    _runUsage = PiUsage.zero;
    _responseChars = 0;
    _toolOutputChars = 0;
    _toolOutputByCall.clear();
    _toolLabels.clear();
    _activity = '';
    _activityKind = ActivityKind.idle;
  }

  void _setActivity(ActivityKind kind, String text) {
    _activityKind = kind;
    _activity = text;
  }

  /// Picks the icon for a tool: a book for reading a file, a pad and pen for
  /// writing one, a terminal for a command, a magnifier for a search.
  static ActivityKind _kindForTool(String name) {
    const readers = {'read', 'ls', 'list_dir', 'view', 'open', 'tail'};
    const writers = {
      'write',
      'edit',
      'multiedit',
      'create',
      'patch',
      'apply_patch'
    };
    const commands = {'bash', 'shell', 'exec', 'run', 'process'};
    const searches = {'grep', 'find', 'glob', 'ripgrep', 'ast_grep'};
    const network = {'web_fetch', 'fetch', 'web_search', 'browser'};
    if (readers.contains(name)) return ActivityKind.reading;
    if (writers.contains(name)) return ActivityKind.editingFile;
    if (commands.contains(name)) return ActivityKind.runningCommand;
    if (searches.contains(name)) return ActivityKind.searching;
    if (network.contains(name)) return ActivityKind.browsing;
    return ActivityKind.tool;
  }

  /// Counts tool output growth per call: `partialResult` is the *latest*
  /// partial result and a tool may replace it rather than extend it, so only
  /// the increase is added.
  void _trackToolOutput(
    String? toolCallId,
    dynamic result,
    String? toolName,
    Map<String, dynamic> args,
  ) {
    final id = toolCallId ?? '';
    final length = _resultText(result).length;
    final previous = _toolOutputByCall[id] ?? 0;
    if (length > previous) {
      _toolOutputByCall[id] = length;
      _toolOutputChars += length - previous;
    }
    if (toolName == null) return;
    final label = _describeTool(toolName, args);
    if (label == toolName && _toolLabels[id] != null) {
      // The update repeated no arguments: keep what the start frame reported.
      _setActivity(_toolLabels[id]!.$2, _toolLabels[id]!.$1);
    } else {
      final kind = _kindForTool(toolName);
      _toolLabels[id] = (label, kind);
      _setActivity(kind, label);
    }
  }

  /// `read package.json`, `bash npm test`, `grep formatTokens`.
  ///
  /// Paths are shortened to the file name: the app bar already shows the
  /// working directory, and an absolute path would push the token counters off
  /// a phone-width status line.
  static String _describeTool(String name, Map<String, dynamic> args) {
    const pathKeys = ['path', 'filePath', 'file', 'notebook_path'];
    const textKeys = ['command', 'pattern', 'query'];
    String? target;
    for (final key in pathKeys) {
      final value = args[key];
      if (value is String && value.isNotEmpty) {
        target = value.replaceAll(r'\', '/').split('/').last;
        break;
      }
    }
    if (target == null) {
      for (final key in textKeys) {
        final value = args[key];
        if (value is String && value.isNotEmpty) {
          target = value;
          break;
        }
      }
    }
    var text = target ?? '';
    if (text.length > 48) text = '${text.substring(0, 45)}…';
    return text.isEmpty ? name : '$name $text';
  }

  Future<void> _refreshSessionStats() async {
    try {
      _sessionStats = await piService.getSessionStats();
    } catch (_) {
      // A backend without get_session_stats simply means the progress line
      // shows this run's numbers only.
    }
  }

  PiMessage _ensureStreamingMessage() {
    if (_streamingMessage != null) return _streamingMessage!;
    _awaitingModel = false; // real content exists now; the bubble shows it
    final message = PiMessage(
      id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      streaming: true,
    );
    _messages.add(message);
    _streamingMessage = message;
    _bumpMessages();
    return message;
  }

  void _addMessage(PiMessage message, {bool streaming = false}) {
    if (message.role == 'assistant') {
      if (streaming) {
        // fromJson leaves this false, and ChatBubble only draws the typing
        // indicator for a streaming message - without this, an assistant reply
        // that has started but has no text yet shows nothing at all.
        message.streaming = true;
        _streamingMessage = message;
      }
      _messages.add(message);
    } else if (message.role == 'user' && message.content.isNotEmpty) {
      // Pi echoes every prompt back as a user message; skip echoes of prompts
      // already shown locally or added by an earlier lifecycle event.
      for (final existing in _messages.reversed) {
        if (existing.role != 'user') break;
        if (existing.content == message.content) return;
      }
      _messages.add(message);
    }
    _bumpMessages();
    _trimMessages();
  }

  void _appendTool(PiTool tool) {
    // Pi reports the same tool call twice (toolcall_end then
    // tool_execution_start); attach it once to the assistant reply.
    for (final message in _messages.reversed) {
      for (final existing in message.toolCalls.reversed) {
        if (tool.id.isNotEmpty && existing.id == tool.id) return;
      }
    }

    final target = _streamingMessage ??
        _messages.lastWhere(
          (m) => m.role == 'assistant',
          orElse: () => _ensureStreamingMessage(),
        );
    target.toolCalls.add(tool);
    _bumpMessages();
  }

  void _finishTool(String? toolCallId, String result) {
    for (final message in _messages.reversed) {
      for (final tool in message.toolCalls.reversed) {
        if (toolCallId != null && tool.id == toolCallId) {
          tool.result = result;
          _bumpMessages();
          return;
        }
      }
    }
    // Fall back to the most recent unfinished tool call.
    for (final message in _messages.reversed) {
      for (final tool in message.toolCalls.reversed) {
        if (tool.result == null) {
          tool.result = result;
          _bumpMessages();
          return;
        }
      }
    }
  }

  void _trimMessages() {
    const maxMessages = 100;
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
  }

  static String _textOf(Map<String, dynamic> message) {
    final content = message['content'];
    if (content is List) {
      return content
          .whereType<Map<String, dynamic>>()
          .where((block) => block['type'] == 'text')
          .map((block) => block['text'] as String? ?? '')
          .join();
    }
    return content as String? ?? '';
  }

  static String _resultText(dynamic result) {
    if (result is Map && result['content'] is List) {
      return (result['content'] as List)
          .whereType<Map<String, dynamic>>()
          .map((block) => block['text'] as String? ?? '')
          .join('\n');
    }
    return result?.toString() ?? '';
  }

  Future<void> submitPrompt([String? input]) async {
    final prompt = (input ?? _userInput).trim();
    if (prompt.isEmpty) return;

    _userInput = '';
    _isLoading = true;
    _awaitingModel = true;
    _error = null;
    _resetRunCounters();
    _messages.add(PiMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: prompt,
      timestamp: DateTime.now(),
    ));
    _bumpMessages();
    _trimMessages();
    _notifyNow();

    try {
      await piService.sendPrompt(prompt);
    } catch (e) {
      _error = 'Error: $e';
      _isLoading = false;
      _awaitingModel = false;
      _notifyNow();
    }
  }

  Future<List<PiSessionInfo>> loadSessions() async {
    _loadingSessions = true;
    _error = null;
    _notifyNow();
    try {
      _sessions = await piService.listSessions();
      _loadingSessions = false;
      _notifyNow();
      return _sessions;
    } catch (e) {
      _loadingSessions = false;
      _error = 'Failed to load sessions: $e';
      _notifyNow();
      return [];
    }
  }

  /// Start a fresh session in the current working directory (like `/new` in the
  /// TUI): the chat is emptied, the directory, model and token counters are left
  /// as they are. The conversation being replaced stays on disk and is still
  /// reachable from the session picker.
  Future<bool> startNewSession() async {
    _error = null;
    _notifyNow();
    try {
      await piService.newSession();
      _messages.clear();
      _streamingMessage = null;
      _bumpMessages();
      _resetRunCounters();
      _awaitingModel = false;
      _isLoading = false;
      _sessionStats = null;
      _userInput = '';
      // Ask the backend what is live now: the new session has its own token
      // totals, and a fresh chat must not keep showing the old context bar.
      await piService.refreshState();
      _notifyNow();
      return true;
    } catch (e) {
      _error = 'Failed to start a new session: $e';
      _notifyNow();
      return false;
    }
  }

  /// Resume a previous Pi session (like `/resume` in the TUI): load it into
  /// the live runtime and restore its conversation in the chat.
  Future<void> resumeSession(String sessionPath) async {
    _isLoading = true;
    _error = null;
    _notifyNow();
    try {
      final history = await piService.resumeSession(sessionPath);
      _loadHistory(history);
      // Pi restores the session in the directory that conversation was recorded
      // in, with its own model and its own token totals. Everything the progress
      // line shows belongs to the session being left behind, so drop it and ask
      // the backend what is live now - otherwise the app bar keeps reporting the
      // working directory from before the resume.
      _resetRunCounters();
      _sessionStats = null;
      await piService.refreshState();
      _isLoading = false;
      _notifyNow();
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to resume session: $e';
      _notifyNow();
    }
  }

  /// Browse the filesystem starting at the current working directory.
  Future<DirListing?> browseDirectory({String? path}) async {
    _loadingDirectories = true;
    _error = null;
    _notifyNow();
    try {
      final listing = await piService.listDirectory(path: path);
      _workingDirectory = listing.current ?? listing.path;
      _workingDirectoryDisplay = listing.cwdDisplay;
      _loadingDirectories = false;
      _notifyNow();
      return listing;
    } catch (e) {
      _loadingDirectories = false;
      _error = 'Failed to browse directories: $e';
      _notifyNow();
      return null;
    }
  }

  /// Point Pi at a new working directory. Pi restarts with a fresh session, so
  /// the current chat is cleared.
  Future<bool> setWorkingDirectory(String path) async {
    _loadingDirectories = true;
    _error = null;
    _notifyNow();
    try {
      final cwd = await piService.setWorkingDirectory(path);
      _workingDirectory = cwd;
      _workingDirectoryDisplay = null;
      // Pick up the backend's shortened "~/..." form for the app bar.
      await piService.refreshState();
      _messages.clear();
      _streamingMessage = null;
      _bumpMessages();
      _loadingDirectories = false;
      _notifyNow();
      return true;
    } catch (e) {
      _loadingDirectories = false;
      _error = 'Failed to set working directory: $e';
      _notifyNow();
      return false;
    }
  }

  /// Rebuild the chat from messages returned by Pi after a session switch.
  void _loadHistory(List<Map<String, dynamic>> history) {
    _messages.clear();
    _streamingMessage = null;
    _bumpMessages();

    for (final raw in history) {
      final role = raw['role'] as String? ?? '';
      final timestamp = raw['timestamp'];
      final when = timestamp is num
          ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt())
          : (timestamp is String
              ? DateTime.tryParse(timestamp) ?? DateTime.now()
              : DateTime.now());

      if (role == 'user') {
        final text = _textOf(raw);
        if (text.isEmpty) continue;
        _messages.add(PiMessage(
          id: raw['id'] as String? ?? 'user-history',
          role: 'user',
          content: text,
          timestamp: when,
        ));
      } else if (role == 'assistant') {
        final message = PiMessage(
          id: raw['id'] as String? ?? 'assistant-history',
          role: 'assistant',
          content: _textOf(raw),
          timestamp: when,
        );
        final blocks = raw['content'];
        if (blocks is List) {
          for (final block in blocks.whereType<Map<String, dynamic>>()) {
            if (block['type'] != 'toolCall') continue;
            message.toolCalls.add(PiTool(
              id: block['id'] as String? ?? '',
              name: block['name'] as String? ?? 'tool',
              arguments:
                  (block['arguments'] as Map<String, dynamic>?) ?? const {},
            ));
          }
        }
        _messages.add(message);
      } else if (role == 'toolResult') {
        // Attach saved tool output to the matching tool call.
        _finishTool(
          raw['toolCallId'] as String?,
          _resultText(raw),
        );
      }
    }

    _trimMessages();
  }

  Future<void> abortCurrentTask() async {
    _awaitingModel = false; // Pi also ends the run, but never leave it stuck
    try {
      await piService.abort();
    } catch (e) {
      _error = 'Failed to abort: $e';
      _notifyNow();
    }
  }

  Future<void> selectModel(PiModel model) async {
    try {
      _isLoading = true;
      _notifyNow();

      await piService.setModel(model.id, model.provider);
      // Read the state back rather than assuming the call worked: it is the only
      // way to know the model really changed, and it puts the picker back on the
      // model Pi is actually using.
      await piService.refreshState();

      _isLoading = false;
      _notifyNow();
    } catch (e) {
      _error = 'Failed to set model: $e';
      _isLoading = false;
      _notifyNow();
    }
  }

  void clearError() {
    _error = null;
    _notifyNow();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
    piService.dispose();
  }
}
