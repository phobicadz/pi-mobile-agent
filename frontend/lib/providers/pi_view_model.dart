import 'package:flutter/material.dart';
import '../services/pi_service.dart';
import '../models/pi_models.dart';

class PiViewModel extends ChangeNotifier {
  final PiService piService;

  PiState? _state;
  final List<PiMessage> _messages = [];
  List<PiModel> _availableModels = [];
  bool _isLoading = false;
  String? _error;
  String _userInput = '';

  /// The assistant reply currently being streamed, if any.
  PiMessage? _streamingMessage;

  PiViewModel({required this.piService}) {
    _initialize();
  }

  // Getters
  PiState? get state => _state;
  List<PiMessage> get messages => _messages;
  List<PiModel> get availableModels => _availableModels;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get userInput => _userInput;
  bool get isConnected => piService.isConnected;

  void _initialize() {
    // Subscribe to Pi service events
    piService.events.listen(_handleEvent);

    piService.stateUpdates.listen((state) {
      _state = state;
      notifyListeners();
    });

    // Load initial data
    _loadModels();
  }

  void setUserInput(String input) {
    _userInput = input;
    notifyListeners();
  }

  Future<void> _loadModels() async {
    try {
      _availableModels = await piService.getAvailableModels();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load models: $e';
      notifyListeners();
    }
  }

  void _handleEvent(PiEvent event) {
    final data = event.data;

    switch (event.type) {
      case 'message_start':
        final message = data['message'];
        if (message is Map<String, dynamic>) {
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
        _streamingMessage = null;
        _isLoading = false;
        break;

      default:
        // Other lifecycle events (turn_start/turn_end/agent_start/...) are not
        // rendered as chat bubbles.
        return;
    }

    notifyListeners();
  }

  void _handleMessageUpdate(Map<String, dynamic> data) {
    final inner = data['assistantMessageEvent'];
    if (inner is! Map<String, dynamic>) return;

    switch (inner['type']) {
      case 'text_delta':
        final delta = inner['delta'] as String? ?? '';
        if (delta.isEmpty) return;
        _ensureStreamingMessage().content += delta;
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
    final message = PiMessage(
      id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      streaming: true,
    );
    _messages.add(message);
    _streamingMessage = message;
    return message;
  }

  void _addMessage(PiMessage message, {bool streaming = false}) {
    if (message.role == 'assistant') {
      if (streaming) {
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
  }

  void _finishTool(String? toolCallId, String result) {
    for (final message in _messages.reversed) {
      for (final tool in message.toolCalls.reversed) {
        if (toolCallId != null && tool.id == toolCallId) {
          tool.result = result;
          return;
        }
      }
    }
    // Fall back to the most recent unfinished tool call.
    for (final message in _messages.reversed) {
      for (final tool in message.toolCalls.reversed) {
        if (tool.result == null) {
          tool.result = result;
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

  Future<void> submitPrompt() async {
    if (_userInput.isEmpty) return;

    final prompt = _userInput;
    _userInput = '';
    _isLoading = true;
    _error = null;
    _messages.add(PiMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: prompt,
      timestamp: DateTime.now(),
    ));
    _trimMessages();
    notifyListeners();

    try {
      await piService.sendPrompt(prompt);
    } catch (e) {
      _error = 'Error: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> abortCurrentTask() async {
    try {
      await piService.abort();
    } catch (e) {
      _error = 'Failed to abort: $e';
      notifyListeners();
    }
  }

  Future<void> selectModel(String modelId) async {
    try {
      _isLoading = true;
      notifyListeners();

      await piService.setModel(modelId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to set model: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    piService.dispose();
  }
}
