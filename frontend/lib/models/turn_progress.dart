import '../models/pi_models.dart';

/// What Pi is doing, as far as the app can tell. Drives the icon in the status
/// line: a brain while it reasons, a pad and pen while it writes text, a book
/// while it reads a file, a terminal while it runs a command.
enum ActivityKind {
  idle,
  waiting,
  thinking,
  writing,
  callingTool,
  reading,
  editingFile,
  runningCommand,
  searching,
  browsing,
  tool,
}

/// Snapshot of the run in flight, shown in the streaming chat bubble.
///
/// Immutable with value equality so the status line rebuilds only when a value
/// actually changed - not on every streamed token.
class TurnProgress {
  /// True while a run is in flight (or has just produced usage to show).
  final bool active;

  /// Which icon to show.
  final ActivityKind kind;

  /// Label next to it: `thinking`, `read index.ts`, `bash npm test`.
  final String activity;

  /// Usage of the responses that already completed in this run. Pi runs one
  /// assistant response per tool round, so this is their sum.
  final PiUsage completed;

  /// Provider-reported usage of the response currently streaming. Often zeros
  /// until the response finishes - `estimatedTokens` covers that case.
  final PiUsage live;

  /// Local estimate (streamed characters / 4) of the tokens produced by the
  /// response in flight, used when the provider reports nothing while streaming.
  final int estimatedTokens;

  /// Characters of tool output produced so far in this run: how much of a file
  /// Pi has read, how much a command has written. Grows while a tool runs.
  final int toolOutputChars;

  /// Context-window usage from the last `get_session_stats` reply, if any.
  final int? contextTokens;
  final int? contextWindow;
  final double? contextPercent;

  /// Seconds the model itself spent generating in this run.
  ///
  /// Built from Pi's own per-response `durationMs` where it reported one, and
  /// from the wall clock between that response starting and finishing where it
  /// did not. Tool time is deliberately excluded: a command that takes two
  /// minutes is not the model being slow, and folding it in is what made the
  /// old throughput figures read wrong.
  final double modelSeconds;

  const TurnProgress({
    required this.active,
    required this.kind,
    required this.activity,
    required this.completed,
    required this.live,
    required this.estimatedTokens,
    required this.toolOutputChars,
    this.contextTokens,
    this.contextWindow,
    this.contextPercent,
    this.modelSeconds = 0,
  });

  static const TurnProgress idle = TurnProgress(
    active: false,
    kind: ActivityKind.idle,
    activity: '',
    completed: PiUsage.zero,
    live: PiUsage.zero,
    estimatedTokens: 0,
    toolOutputChars: 0,
  );

  /// Tokens produced by this run, provider-reported where available.
  int get producedTokens =>
      completed.produced +
      (live.produced > estimatedTokens ? live.produced : estimatedTokens);

  /// True when the produced-token count is our estimate, not Pi's numbers.
  bool get estimated => live.produced == 0 && estimatedTokens > 0;

  /// Everything the model generated in this run, thinking included.
  ///
  /// A rate is measured over the tokens that were actually decoded, and
  /// reasoning tokens are decoded in the same window and on the same clock as
  /// the reply text. Leaving them out makes a model that thinks look slower
  /// than it is.
  int get generatedTokens =>
      completed.output +
      completed.reasoning +
      ((live.output + live.reasoning) > estimatedTokens
          ? live.output + live.reasoning
          : estimatedTokens);

  /// Tokens the model generated per second it spent generating.
  ///
  /// Zero until there is a window long enough to divide by, so the status line
  /// can say "starting" rather than invent a number from the first token.
  double get tokensPerSecond =>
      modelSeconds >= 0.5 ? generatedTokens / modelSeconds : 0;

  /// Tokens consumed by everything Pi has in context right now.
  int get consumedTokens =>
      completed.totalTokens + live.totalTokens + (contextTokens ?? 0);

  @override
  bool operator ==(Object other) =>
      other is TurnProgress &&
      other.active == active &&
      other.kind == kind &&
      other.activity == activity &&
      other.completed == completed &&
      other.live == live &&
      other.estimatedTokens == estimatedTokens &&
      other.toolOutputChars == toolOutputChars &&
      other.contextTokens == contextTokens &&
      other.contextWindow == contextWindow &&
      other.contextPercent == contextPercent &&
      other.modelSeconds == modelSeconds;

  @override
  int get hashCode => Object.hash(
        active,
        kind,
        activity,
        completed,
        live,
        estimatedTokens,
        toolOutputChars,
        contextTokens,
        contextWindow,
        contextPercent,
        modelSeconds,
      );
}
