class PiState {
  final String? currentModel;
  final int? messageCount;
  final bool isProcessing;
  final String? systemPrompt;
  final Map<String, dynamic>? raw;

  PiState({
    this.currentModel,
    this.messageCount,
    this.isProcessing = false,
    this.systemPrompt,
    this.raw,
  });

  factory PiState.fromJson(Map<String, dynamic> json) {
    // The backend reports the model as an object; only its id is needed here.
    final model = json['model'];
    final modelId = model is Map
        ? model['id'] as String?
        : model as String?;

    return PiState(
      currentModel: modelId,
      messageCount: json['messageCount'] as int?,
      isProcessing: json['isStreaming'] as bool? ?? json['isProcessing'] as bool? ?? false,
      systemPrompt: json['systemPrompt'] as String?,
      raw: json,
    );
  }

  PiState copyWith({
    String? currentModel,
    int? messageCount,
    bool? isProcessing,
    String? systemPrompt,
  }) {
    return PiState(
      currentModel: currentModel ?? this.currentModel,
      messageCount: messageCount ?? this.messageCount,
      isProcessing: isProcessing ?? this.isProcessing,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      raw: raw,
    );
  }
}

class PiMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  String content;
  final DateTime timestamp;
  final List<PiTool> toolCalls;

  /// True while Pi is still streaming this reply.
  bool streaming;

  PiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    List<PiTool>? toolCalls,
    this.streaming = false,
  }) : toolCalls = toolCalls ?? [];

  factory PiMessage.fromJson(Map<String, dynamic> json) {
    // Pi serialises message content as a list of blocks; join the text ones.
    final rawContent = json['content'];
    String text;
    if (rawContent is List) {
      text = rawContent
          .whereType<Map<String, dynamic>>()
          .where((block) => block['type'] == 'text')
          .map((block) => block['text'] as String? ?? '')
          .join();
    } else {
      text = rawContent as String? ?? '';
    }

    return PiMessage(
      id: json['id'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      content: text,
      timestamp: json['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      toolCalls: (json['toolCalls'] as List<dynamic>?)
          ?.map((e) => PiTool.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PiTool {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  String? result;

  PiTool({
    required this.name,
    required this.arguments,
    this.id = '',
    this.result,
  });

  factory PiTool.fromJson(Map<String, dynamic> json) {
    return PiTool(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      arguments: json['arguments'] as Map<String, dynamic>? ?? {},
      result: json['result'] as String?,
    );
  }
}

class PiModel {
  final String id;
  final String name;
  final String provider;
  final bool available;

  PiModel({
    required this.id,
    required this.name,
    required this.provider,
    this.available = true,
  });

  factory PiModel.fromJson(Map<String, dynamic> json) {
    return PiModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      available: json['available'] as bool? ?? true,
    );
  }
}

class PiSessionInfo {
  final String path;
  final String id;
  final String cwd;
  final String? name;
  final String preview;
  final int messageCount;
  final DateTime modified;

  PiSessionInfo({
    required this.path,
    required this.id,
    required this.cwd,
    required this.preview,
    required this.messageCount,
    required this.modified,
    this.name,
  });

  factory PiSessionInfo.fromJson(Map<String, dynamic> json) {
    return PiSessionInfo(
      path: json['path'] as String? ?? '',
      id: json['id'] as String? ?? '',
      cwd: json['cwd'] as String? ?? '',
      name: json['name'] as String?,
      preview: json['preview'] as String? ?? '',
      messageCount: json['messageCount'] as int? ?? 0,
      modified: DateTime.tryParse(json['modified'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class PiEvent {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  PiEvent({
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory PiEvent.fromJson(Map<String, dynamic> json) {
    // The backend wraps Pi's records as { type: "pi_event", event: {...} }.
    // Expose the inner record so consumers switch on the real event type.
    final inner = json['event'] as Map<String, dynamic>? ?? json;
    return PiEvent(
      type: inner['type'] as String? ?? '',
      data: inner,
      timestamp: DateTime.now(),
    );
  }
}
