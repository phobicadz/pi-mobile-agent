import 'dart:async';

import 'package:flutter/material.dart';
import '../services/pi_service.dart';
import '../models/pi_models.dart';

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
      case 'turn_start':
        _awaitingModel = true;
        break;

      case 'message_start':
        final message = data['message'];
        if (message is Map<String, dynamic>) {
          if (message['role'] == 'assistant') _awaitingModel = false;
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
          final text = _textOf(message);
          if (_streamingMessage != null) {
            if (text.isNotEmpty) _streamingMessage!.content = text;
            _streamingMessage!.streaming = false;
            _streamingMessage = null;
          } else {
            final parsed = PiMessage.fromJson(message);
            if (parsed.content.isNotEmpty || parsed.toolCalls.isNotEmpty) {
              _addMessage(parsed);
            }
          }
        }
        break;

      case 'tool_execution_start':
        _appendTool(PiTool(
          id: data['toolCallId'] as String? ?? '',
          name: data['toolName'] as String? ?? 'tool',
          arguments: (data['args'] as Map<String, dynamic>?) ?? const {},
        ));
        break;

      case 'tool_execution_end':
        _finishTool(
          data['toolCallId'] as String?,
          _resultText(data['result']),
        );
        break;

      case 'agent_end':
        _streamingMessage?.streaming = false; // never leave a spinner spinning
        _streamingMessage = null;
        _awaitingModel = false;
        _isLoading = false;
        break;

      default:
        // Other lifecycle events (turn_start/turn_end/agent_start/...) are not
        // rendered as chat bubbles.
        return;
    }

    _scheduleNotify();
  }

  void _handleMessageUpdate(Map<String, dynamic> data) {
    final inner = data['assistantMessageEvent'];
    if (inner is! Map<String, dynamic>) return;

    switch (inner['type']) {
      case 'text_delta':
        final delta = inner['delta'] as String? ?? '';
        if (delta.isEmpty) return;
        _ensureStreamingMessage().content += delta;
        _bumpMessages();
        break;

      case 'toolcall_end':
        final call = inner['toolCall'];
        if (call is Map<String, dynamic>) {
          _appendTool(PiTool(
            id: call['id'] as String? ?? '',
            name: call['name'] as String? ?? 'tool',
            arguments: (call['arguments'] as Map<String, dynamic>?) ?? const {},
          ));
        }
        break;
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

  /// Resume a previous Pi session (like `/resume` in the TUI): load it into
  /// the live runtime and restore its conversation in the chat.
  Future<void> resumeSession(String sessionPath) async {
    _isLoading = true;
    _error = null;
    _notifyNow();
    try {
      final history = await piService.resumeSession(sessionPath);
      _loadHistory(history);
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

  Future<void> selectModel(String modelId) async {
    try {
      _isLoading = true;
      _notifyNow();

      await piService.setModel(modelId);

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
