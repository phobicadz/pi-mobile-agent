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
  final _notificationsController = StreamController<bool>.broadcast();
  final Map<String, Completer> _pendingRequests = {};
  bool _isConnected = false;
  Timer? _reconnectTimer;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  PiService({this.serverUrl = 'ws://localhost:3000'});

  Stream<PiEvent> get events => _messageController.stream;
  Stream<PiState> get stateUpdates => _stateController.stream;

  /// Whether a finished run announces itself, as the backend says it is set.
  ///
  /// The backend is the owner of this one and not the browser: the notice it
  /// gates is sent by the `notify-completion` Pi extension in the agent's own
  /// process, so the setting has to be one thing every device reads the same way.
  /// The backend sends it unprompted on connect, which is what makes a switch
  /// opened on a second device show the truth rather than its own guess.
  Stream<bool> get notificationUpdates => _notificationsController.stream;
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
      } else if (type == 'notifications_state') {
        // The backend's own state, pushed on connect and after any device
        // changes it. Not a command reply: nothing asked for it a moment ago.
        _notificationsController.add(data['enabled'] == true);
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
    Duration? timeout,
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
        timeout ?? const Duration(seconds: 30),
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

  /// Send a prompt, optionally with images attached.
  ///
  /// The images are Pi's own `ImageContent` shape (`toJson` on [PiImage] is
  /// that shape). Whether the model in play accepts them is decided before this
  /// is called - the backend validates the payload but does not know which model
  /// the user picked, and a model that cannot see would reject the whole prompt.
  Future<void> sendPrompt(String message, {List<PiImage> images = const []}) async {
    final response = await _sendCommand(
      'prompt',
      params: {
        'message': message,
        if (images.isNotEmpty)
          'images': images.map((image) => image.toJson()).toList(),
      },
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

  /// The user's own GitHub repositories, most recently pushed first.
  ///
  /// The backend reads these from the GitHub CLI on this machine, so it can
  /// reach private repositories without the app ever holding a token.
  Future<List<GitHubRepo>> listGitHubRepos() async {
    final response = await _sendCommand('list_repos');
    final data = unwrapData(response, command: 'list_repos');
    return (data['repos'] as List<dynamic>? ?? [])
        .map((e) => GitHubRepo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Clone [repo] (`owner/name`, or a github.com URL) into [path].
  ///
  /// Omit [path] to clone into the directory Pi is working in. Returns the
  /// directory the clone made.
  ///
  /// The timeout is longer than for any other command because a first clone of
  /// a real repository is the case this has to survive; the backend gives up at
  /// five minutes and says so, and this waits past that so its reason — not a
  /// client-side "command timeout" — is what comes back.
  Future<String> cloneGitHubRepo({required String repo, String? path}) async {
    final response = await _sendCommand(
      'clone_repo',
      params: {'repo': repo, if (path != null) 'path': path},
      timeout: const Duration(minutes: 6),
    );
    final data = unwrapData(response, command: 'clone_repo');
    return data['path'] as String? ?? '';
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

  /// Give a saved session a display name (`rename_session`).
  ///
  /// The backend decides how: the session the live Pi is in goes through Pi, so
  /// its own idea of the name stays in step with the file, and every other one
  /// is a file nobody has open and is appended to directly. Either way the name
  /// is what the picker shows instead of the first message, and what Pi's own
  /// `/resume` shows too.
  ///
  /// A null [name] clears it, which is what Pi's `/name` does with an empty one.
  Future<void> renameSession(String sessionPath, String? name) async {
    final response = await _sendCommand(
      'rename_session',
      params: {'sessionPath': sessionPath, 'name': name},
    );
    if (response['success'] == false) {
      throw Exception('Rename failed: ${response['error']}');
    }
  }

  /// Ask the model what a session should be called (`generate_session_title`).
  ///
  /// A suggestion, never an applied name: what a model guessed about a
  /// conversation is worth showing someone before it becomes that conversation's
  /// label. It is a model call rather than a socket read, so it is given longer
  /// than the 30 seconds a command over a LAN link normally needs.
  Future<String> suggestSessionTitle(String sessionPath) async {
    final response = await _sendCommand(
      'generate_session_title',
      params: {'sessionPath': sessionPath},
      timeout: const Duration(seconds: 100),
    );
    if (response['success'] == false) {
      throw Exception('Naming failed: ${response['error']}');
    }
    final data = unwrapData(response, command: 'generate_session_title');
    final title = (data['title'] as String? ?? '').trim();
    if (title.isEmpty) {
      throw Exception('The model returned no name');
    }
    return title;
  }

  /// Remove a saved session (`delete_session`).
  ///
  /// The backend tries `trash` and falls back to unlinking, which is the order
  /// Pi's own session picker uses — so a session removed from the app and one
  /// removed from the TUI end up in the same place, and where a trashing tool
  /// exists that place is recoverable. It refuses the session the live Pi is in:
  /// that file is open and still being written to.
  Future<void> deleteSession(String sessionPath) async {
    final response = await _sendCommand(
      'delete_session',
      params: {'sessionPath': sessionPath},
    );
    if (response['success'] == false) {
      throw Exception('Delete failed: ${response['error']}');
    }
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

  /// The conversation the live Pi session is actually holding.
  ///
  /// The backend's Pi process outlives the browser: closing the tab leaves the
  /// session running in its directory, and reconnecting joins that same session.
  /// An app that never asks what it contains shows an empty chat over a
  /// conversation with a history in it - while the app bar, which is fed from
  /// the backend's state, correctly reports that session's directory and its
  /// context figures. The numbers then look like they belong to a conversation
  /// that was never loaded.
  Future<List<Map<String, dynamic>>> loadCurrentHistory() async {
    final response = await _sendCommand('get_messages');
    final data = unwrapData(response, command: 'get_messages');
    return (data['messages'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
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
    // After the switch, "the current session" *is* the one being resumed, so the
    // history is read the same way rather than duplicated here.
    return loadCurrentHistory();
  }

  /// Report what the browser and Flutter each think the screen is, along with
  /// the safe areas the app is laying out under. The backend only logs it: this
  /// is how a layout problem that only shows on a phone gets diagnosed from the
  /// service log instead of from a screenshot.
  Future<void> sendClientMetrics(Map<String, dynamic> metrics) async {
    if (!_isConnected) return;
    await _sendCommand('client_metrics', params: {'metrics': metrics});
  }

  /// Move the switch the agent acts on.
  ///
  /// Sent to the backend rather than held here: the notice this controls is the
  /// one the Pi extension sends to Home Assistant, which is a different process
  /// that only the backend can talk to.
  Future<void> setNotifications(bool enabled) async {
    if (!_isConnected) return;
    await _sendCommand('set_notifications', params: {'enabled': enabled});
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
    _notificationsController.close();
  }
}
