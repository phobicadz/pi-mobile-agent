class PiState {
  final String? currentModel;

  /// The provider the current model belongs to. Pi's `set_model` takes a provider
  /// and a model id rather than one string, and this is also what labels the
  /// model Pi is actually using when it is not among the ones Pi offered.
  final String? currentModelProvider;
  final int? messageCount;
  final bool isProcessing;
  final String? systemPrompt;

  /// Directory the backend's Pi process is running in (reported by the backend;
  /// Pi's own RPC state does not include it).
  final String? cwd;

  /// Same directory, shortened to "~" / "~/..." for display.
  final String? cwdDisplay;
  final Map<String, dynamic>? raw;

  PiState({
    this.currentModel,
    this.currentModelProvider,
    this.messageCount,
    this.isProcessing = false,
    this.systemPrompt,
    this.cwd,
    this.cwdDisplay,
    this.raw,
  });

  factory PiState.fromJson(Map<String, dynamic> json) {
    // The backend reports the model as an object; its id and provider together
    // are what name a model to Pi.
    final model = json['model'];
    final modelId = model is Map ? model['id'] as String? : model as String?;

    return PiState(
      currentModel: modelId,
      currentModelProvider: model is Map ? model['provider'] as String? : null,
      messageCount: json['messageCount'] as int?,
      isProcessing: json['isStreaming'] as bool? ??
          json['isProcessing'] as bool? ??
          false,
      systemPrompt: json['systemPrompt'] as String?,
      cwd: json['cwd'] as String?,
      cwdDisplay: json['cwdDisplay'] as String?,
      raw: json,
    );
  }

  PiState copyWith({
    String? currentModel,
    String? currentModelProvider,
    int? messageCount,
    bool? isProcessing,
    String? systemPrompt,
    String? cwd,
    String? cwdDisplay,
  }) {
    return PiState(
      currentModel: currentModel ?? this.currentModel,
      currentModelProvider: currentModelProvider ?? this.currentModelProvider,
      messageCount: messageCount ?? this.messageCount,
      isProcessing: isProcessing ?? this.isProcessing,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      cwd: cwd ?? this.cwd,
      cwdDisplay: cwdDisplay ?? this.cwdDisplay,
      raw: raw,
    );
  }
}

/// Token usage of one assistant response, exactly as Pi reports it.
///
/// Pi sends this on every `message_update` (`usage`) and on the finished
/// assistant message (`message.usage`). It is cumulative **for the current
/// assistant response only** — the next tool round starts a fresh count — so
/// turn totals are accumulated from the completed responses, not from the
/// streaming frames. Some providers report zeros until the response completes;
/// callers should fall back to a streamed-character estimate then.
class PiUsage {
  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;
  final int totalTokens;

  /// Tokens spent on extended thinking, when the provider reports them.
  final int reasoning;
  final double cost;

  const PiUsage({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    this.totalTokens = 0,
    this.reasoning = 0,
    this.cost = 0,
  });

  static const PiUsage zero = PiUsage();

  factory PiUsage.fromJson(dynamic json) {
    if (json is! Map) return zero;
    final cost = json['cost'];
    return PiUsage(
      input: _asInt(json['input']),
      output: _asInt(json['output']),
      cacheRead: _asInt(json['cacheRead']),
      cacheWrite: _asInt(json['cacheWrite']),
      totalTokens: _asInt(json['totalTokens'] ?? json['total']),
      reasoning: _asInt(json['reasoning']),
      cost: cost is Map ? _asDouble(cost['total']) : 0,
    );
  }

  bool get isEmpty =>
      input == 0 &&
      output == 0 &&
      cacheRead == 0 &&
      cacheWrite == 0 &&
      totalTokens == 0;

  /// Anything the model produced for this response, thinking included.
  int get produced => output;

  PiUsage operator +(PiUsage other) => PiUsage(
        input: input + other.input,
        output: output + other.output,
        cacheRead: cacheRead + other.cacheRead,
        cacheWrite: cacheWrite + other.cacheWrite,
        totalTokens: totalTokens + other.totalTokens,
        reasoning: reasoning + other.reasoning,
        cost: cost + other.cost,
      );

  @override
  bool operator ==(Object other) =>
      other is PiUsage &&
      other.input == input &&
      other.output == output &&
      other.cacheRead == cacheRead &&
      other.cacheWrite == cacheWrite &&
      other.totalTokens == totalTokens &&
      other.reasoning == reasoning &&
      other.cost == cost;

  @override
  int get hashCode => Object.hash(
      input, output, cacheRead, cacheWrite, totalTokens, reasoning, cost);

  static int _asInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
  static double _asDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}

/// Session-wide totals from the backend's `get_session_stats` command.
class PiSessionStats {
  final PiUsage tokens;
  final double cost;

  /// Current context-window usage, which Pi omits right after compaction.
  final int? contextTokens;
  final int? contextWindow;
  final double? contextPercent;

  const PiSessionStats({
    required this.tokens,
    this.cost = 0,
    this.contextTokens,
    this.contextWindow,
    this.contextPercent,
  });

  factory PiSessionStats.fromJson(Map<String, dynamic> json) {
    final context = json['contextUsage'];
    return PiSessionStats(
      tokens: PiUsage.fromJson(json['tokens']),
      cost: json['cost'] is num ? (json['cost'] as num).toDouble() : 0,
      contextTokens: context is Map ? PiUsage._asInt(context['tokens']) : null,
      contextWindow:
          context is Map ? PiUsage._asInt(context['contextWindow']) : null,
      contextPercent:
          context is Map ? PiUsage._asDouble(context['percent']) : null,
    );
  }
}

class PiMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  String content;
  final DateTime timestamp;
  final List<PiTool> toolCalls;

  /// Provider-reported usage of a finished assistant response. Null while
  /// streaming, and for tool results (Pi reports none there).
  PiUsage? usage;

  /// Why Pi ended this response, as the provider reported it: `stop`, `error`,
  /// `length`, `aborted`… Null while it is still streaming.
  String? stopReason;

  /// The provider's own description of a failed response - a model the account
  /// cannot use, an expired login, a context window full. Without it the app
  /// shows a failed run as silence: the assistant message exists, has no text,
  /// and a model that never answers looks like a model that is not answering.
  String? errorMessage;

  /// True while Pi is still streaming this reply.
  bool streaming;

  PiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    List<PiTool>? toolCalls,
    this.usage,
    this.stopReason,
    this.errorMessage,
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
      usage: json['usage'] == null ? null : PiUsage.fromJson(json['usage']),
      stopReason: json['stopReason'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  /// What the copy button puts on the clipboard: the reply text, or - for a
  /// bubble that is only tool calls - the calls and their results, which is the
  /// text that bubble actually shows.
  String get copyableText {
    if (content.isNotEmpty) return content;
    if (toolCalls.isEmpty) return '';
    return toolCalls.map((tool) => tool.toPlainText()).join('\n\n');
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

  /// The call as plain text, for copying a bubble that is only tool calls:
  /// `bash(command: ls)` followed by what it printed.
  String toPlainText() {
    final args = arguments.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
    final header = args.isEmpty ? name : '$name($args)';
    final body = result ?? '';
    return body.isEmpty ? header : '$header\n$body';
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

class DirEntry {
  final String name;
  final String path;

  DirEntry({required this.name, required this.path});

  factory DirEntry.fromJson(Map<String, dynamic> json) {
    return DirEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }
}

class DirListing {
  final String path;
  final String? parent;
  final List<DirEntry> roots;
  final List<DirEntry> entries;
  final String? current;

  /// [current] shortened to "~" / "~/..." for display.
  final String? cwdDisplay;
  final List<String> recent;

  DirListing({
    required this.path,
    this.parent,
    required this.roots,
    required this.entries,
    this.current,
    this.cwdDisplay,
    required this.recent,
  });

  factory DirListing.fromJson(Map<String, dynamic> json) {
    return DirListing(
      path: json['path'] as String? ?? '',
      parent: json['parent'] as String?,
      roots: (json['roots'] as List<dynamic>? ?? [])
          .map((e) => DirEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      entries: (json['entries'] as List<dynamic>? ?? [])
          .map((e) => DirEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      current: json['current'] as String?,
      cwdDisplay: json['cwdDisplay'] as String?,
      recent: (json['recent'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
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
