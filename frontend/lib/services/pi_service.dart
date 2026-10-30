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

  /// Every backend reply is an envelope:
  /// `{type, id, command, success, data, error}`. Callers must read the payload
  /// out of `data` — parsing the envelope itself yields an all-empty result, and
  /// that is what made the directory browser show no folders at all.
  static Map<String, dynamic> unwrapData(
    Map<String, dynamic> response, {
    required String command,
  }) {
    if (response['type'] == 'error' || response['success'] == false) {
      throw Exception(response['error'] ?? '$command failed');
    }
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    // Commands with no payload (abort, set_model) still answer with an envelope.
    return const {};
  }

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
      // Ask for the current state as soon as the socket is up so the UI knows
      // the model and working directory without waiting for a turn to finish.
      unawaited(_fetchState());
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

  /// Switch the model Pi answers with. Pi names a model by *provider* and
  /// *model id* - sending only a bare `model` makes Pi answer
  /// "Model not found: undefined/undefined", which is why the model picker used
  /// to look like it did nothing at all.
  Future<void> setModel(String modelId, String provider) async {
    await _sendCommand('set_model',
        params: {'provider': provider, 'modelId': modelId});
  }

  Future<List<PiModel>> getAvailableModels() async {
    final response = await _sendCommand('get_available_models');
    final data = unwrapData(response, command: 'get_available_models');

    final models = (data['models'] as List<dynamic>? ?? [])
        .map((e) => PiModel.fromJson(e as Map<String, dynamic>))
        .toList();

    return models;
  }

  /// Browse a directory on the machine running Pi. Omit [path] to browse the
  /// current working directory.
  Future<DirListing> listDirectory({String? path}) async {
    final response = await _sendCommand('list_dir', params: {
      if (path != null) 'path': path,
    });
    return DirListing.fromJson(unwrapData(response, command: 'list_dir'));
  }

  /// List all files and directories in a path. Omit [path] to list the
  /// current working directory.
  Future<FileListing> listFiles({String? path}) async {
    final response = await _sendCommand('list_files', params: {
      if (path != null) 'path': path,
    });
    return FileListing.fromJson(unwrapData(response, command: 'list_files'));
  }

  /// Create a new directory inside [path]. Omit [path] to create it in the
  /// current working directory. Returns the created path.
  Future<String> createDirectory({required String name, String? path}) async {
    final response = await _sendCommand('create_dir', params: {
      'name': name,
      if (path != null) 'path': path,
    });
    final data = unwrapData(response, command: 'create_dir');
    return data['path'] as String? ?? name;
  }

  /// Read the contents of a text file.
  Future<FileContent> readFile(String path) async {
    final response = await _sendCommand('read_file', params: {'path': path});
    return FileContent.fromJson(unwrapData(response, command: 'read_file'));
  }

  /// Point Pi at a new working directory. Pi restarts with a fresh session, so
  /// the current chat history no longer applies.
  Future<String> setWorkingDirectory(String path) async {
    final response = await _sendCommand('set_cwd', params: {'path': path});
    final data = unwrapData(response, command: 'set_cwd');
    return data['cwd'] as String? ?? path;
  }

  /// Token/cost totals for the whole session, including the current context
  /// window usage. Fetched when a turn settles so the progress bar can show
  /// real numbers instead of only what the current response reported.
  Future<PiSessionStats> getSessionStats() async {
    final response = await _sendCommand('get_session_stats');
    return PiSessionStats.fromJson(
      unwrapData(response, command: 'get_session_stats'),
    );
  }

  Future<List<PiSessionInfo>> listSessions() async {
    final response = await _sendCommand('list_sessions');
    final data = unwrapData(response, command: 'list_sessions');
    return (data['sessions'] as List<dynamic>? ?? [])
        .map((e) => PiSessionInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Start a fresh Pi session in the directory Pi is already working in (like
  /// `/new` in the TUI). The conversation being left behind stays on disk, so
  /// the session picker can load it again.
  Future<void> newSession() async {
    final response = await _sendCommand('new_session');
    if (response['success'] == false) {
      throw Exception('New session failed: ${response['error']}');
    }
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
    final data = unwrapData(history, command: 'get_messages');
    return (data['messages'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  /// Report what the browser and Flutter each think the screen is, along with
  /// the safe areas the app is laying out under. The backend only logs it: this
  /// is how a layout problem that only shows on a phone gets diagnosed from the
  /// service log instead of from a screenshot.
  Future<void> sendClientMetrics(Map<String, dynamic> metrics) async {
    if (!_isConnected) return;
    await _sendCommand('client_metrics', params: {'metrics': metrics});
  }

  /// Ask the backend for its current state (model, working directory, ...).
  /// The reply arrives on [stateUpdates]. Safe to call from tests: it does
  /// nothing while the socket is down.
  Future<void> refreshState() async {
    if (!_isConnected) return;
    await _fetchState();
  }

  Future<void> _fetchState() async {
    try {
      final response = await _sendCommand('get_state');
      final state =
          PiState.fromJson(unwrapData(response, command: 'get_state'));
      _stateController.add(state);
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
