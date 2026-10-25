import '../models/pi_models.dart';

/// Snapshot of what Pi is doing right now, for the progress line.
///
/// Immutable and with value equality so a Selector can rebuild the progress bar
/// only when a number actually changed, not on every stream frame.
class TurnProgress {
  /// True while a run is in flight (or has just produced usage to show).
  final bool active;

  /// Human-readable activity: `thinking`, `read package.json`, `bash npm test`.
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

  const TurnProgress({
    required this.active,
    required this.activity,
    required this.completed,
    required this.live,
    required this.estimatedTokens,
    required this.toolOutputChars,
    this.contextTokens,
    this.contextWindow,
    this.contextPercent,
  });

  static const TurnProgress idle = TurnProgress(
    active: false,
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

  /// Tokens consumed by everything Pi has in context right now.
  int get consumedTokens =>
      completed.totalTokens +
      live.totalTokens +
      (contextTokens ?? 0);

  @override
  bool operator ==(Object other) =>
      other is TurnProgress &&
      other.active == active &&
      other.activity == activity &&
      other.completed == completed &&
      other.live == live &&
      other.estimatedTokens == estimatedTokens &&
      other.toolOutputChars == toolOutputChars &&
      other.contextTokens == contextTokens &&
      other.contextWindow == contextWindow &&
      other.contextPercent == contextPercent;

  @override
  int get hashCode => Object.hash(
        active,
        activity,
        completed,
        live,
        estimatedTokens,
        toolOutputChars,
        contextTokens,
        contextWindow,
        contextPercent,
      );
}
