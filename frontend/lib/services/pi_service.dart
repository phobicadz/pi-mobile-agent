import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import '../models/pi_models.dart';

class PiService {
  late WebSocketChannel _channel;
  final String serverUrl;
  final _messageController = StreamController<PiEvent>.broadcast();
  final _stateController = StreamController<PiState>.broadcast();
  final Map<String, Completer> _pendingRequests = {};
  bool _isConnected = false;
  Timer? _reconnectTimer;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  PiService({this.serverUrl = 'ws://localhost:3000'});

  Stream<PiEvent> get events => _messageController.stream;
  Stream<PiState> get stateUpdates => _stateController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      
      _channel.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleConnectionClosed,
      );

      _isConnected = true;
      print('Connected to Pi backend');
    } catch (e) {
      print('Failed to connect: $e');
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'response') {
        // Handle command response
        final id = data['id'] as String?;
        if (id != null && _pendingRequests.containsKey(id)) {
          final completer = _pendingRequests.remove(id)!;
          completer.complete(data);
        }
      } else if (type == 'pi_event') {
        // Handle Pi session events
        final event = PiEvent.fromJson(data);
        _messageController.add(event);
        
        // Update state when the agent finishes a turn (message_update fires
        // many times per reply, so polling on it would flood the backend).
        if (data['event']['type'] == 'agent_settled') {
          _fetchState();
        }
      } else if (type == 'error') {
        print('Pi backend error: ${data['error']}');
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }

  void _handleError(dynamic error) {
    print('WebSocket error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _handleConnectionClosed() {
    print('Connection closed');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, connect);
  }

  Future<Map<String, dynamic>> _sendCommand(
    String command, {
    Map<String, dynamic>? params,
  }) async {
    if (!_isConnected) {
      throw Exception('Not connected to Pi backend');
    }

    const uuid = Uuid();
    final id = uuid.v4();
    
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final message = {
      'id': id,
      'command': command,
      ...?params,
    };

    try {
      _channel.sink.add(jsonEncode(message));
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingRequests.remove(id);
          throw Exception('Command timeout: $command');
        },
      );
    } catch (e) {
      _pendingRequests.remove(id);
      rethrow;
    }
  }

  Future<void> sendPrompt(String message) async {
    final response = await _sendCommand(
      'prompt',
      params: {'message': message},
    );
    if (!response['success']) {
      throw Exception('Prompt failed: ${response['error']}');
    }
  }

  Future<void> abort() async {
    await _sendCommand('abort');
  }

  Future<void> setModel(String model) async {
    await _sendCommand('set_model', params: {'model': model});
  }

  Future<List<PiModel>> getAvailableModels() async {
    final response = await _sendCommand('get_available_models');
    final data = response['data'] as Map<String, dynamic>?;
    
    if (data == null) return [];
    
    final models = (data['models'] as List<dynamic>? ?? [])
        .map((e) => PiModel.fromJson(e as Map<String, dynamic>))
        .toList();
    
    return models;
  }

  Future<List<PiSessionInfo>> listSessions() async {
    final response = await _sendCommand('list_sessions');
    final data = response['data'] as Map<String, dynamic>?;
    if (data == null) return [];
    return (data['sessions'] as List<dynamic>? ?? [])
        .map((e) => PiSessionInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Loads a saved session into the live Pi runtime. Returns the restored
  /// conversation history so the UI can hydrate it.
  Future<List<Map<String, dynamic>>> resumeSession(String sessionPath) async {
    final response = await _sendCommand(
      'resume_session',
      params: {'sessionPath': sessionPath},
    );
    if (!response['success']) {
      throw Exception('Resume failed: ${response['error']}');
    }
    final history = await _sendCommand('get_messages');
    final data = history['data'] as Map<String, dynamic>?;
    return (data?['messages'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  Future<void> _fetchState() async {
    try {
      final response = await _sendCommand('get_state');
      if (response['success']) {
        final state = PiState.fromJson(response['data'] as Map<String, dynamic>);
        _stateController.add(state);
      }
    } catch (e) {
      print('Error fetching state: $e');
    }
  }

  void dispose() {
    _reconnectTimer?.cancel();
    // connect() may never have succeeded, so the channel may not exist.
    if (_isConnected) {
      _channel.sink.close();
    }
    _messageController.close();
    _stateController.close();
  }
}
