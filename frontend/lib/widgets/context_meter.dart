import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pi_models.dart';
import '../providers/pi_view_model.dart';
import '../utils/format.dart';

/// Context-window usage in the app bar.
///
/// The percentage is Pi's own (`getContextUsage`, reported through
/// `get_session_stats`), not a figure this app infers from the tokens it has
/// watched go past. Pi is the only thing that knows what it is about to send.
///
/// It sits in the bar rather than in the chat for the same reason the connection
/// dot does: it is not a control and not a result, it is the number that tells
/// you whether this conversation is close to running out of room - the kind of
/// thing that is only useful before you ask the next question.
///
/// Nothing is shown until Pi has reported a figure. A blank reads as "not
/// measured", which is true; `0%` would read as "the context is empty", which
/// is a different lie, and one you would act on.
class ContextMeter extends StatelessWidget {
  const ContextMeter({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<PiViewModel, PiSessionStats?>(
      selector: (_, viewModel) => viewModel.sessionStats,
      builder: (context, stats, _) {
        final percent = stats?.contextPercent;
        if (percent == null || percent <= 0) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        // The colours say how close to full this is, because that is the only
        // reason to look at a context meter at all. 80% is where Pi's own
        // compaction starts getting close; past 95% the next long file read is
        // what ends the conversation.
        final color = percent >= 95
            ? theme.colorScheme.error
            : percent >= 80
                ? (isDark ? const Color(0xFFFFB74D) : const Color(0xFF8D6E00))
                : theme.colorScheme.onSurfaceVariant;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Tooltip(
              message: _tooltip(stats!, percent),
              child: Text(
                '${percent.round()}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// `60k / 200k context tokens · 30%`, or the percentage alone when Pi
  /// reported a percentage without the numbers behind it.
  static String _tooltip(PiSessionStats stats, double percent) {
    final tokens = stats.contextTokens;
    final window = stats.contextWindow;
    if (tokens == null || window == null || window <= 0) {
      return 'Context used: ${percent.toStringAsFixed(1)}%';
    }
    return 'Context used: ${formatTokens(tokens)} / ${formatTokens(window)} '
        'tokens (${percent.toStringAsFixed(1)}%)';
  }
}
