import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/turn_progress.dart';
import '../providers/pi_view_model.dart';

/// The busy indicator, inside the streaming chat bubble: an icon that matches
/// what Pi is actually doing (brain while it reasons, pad and pen while it
/// writes, book while it reads a file, terminal while it runs a command), a
/// label, and how many tokens that has cost so far.
///
/// It is the only busy indicator in the app - the bubble itself shows nothing
/// else - and it rebuilds only when a value in [PiViewModel.progress] changes,
/// because the selected [TurnProgress] has value equality and the view model
/// coalesces Pi's stream frames.
class TurnStatusRow extends StatelessWidget {
  const TurnStatusRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<PiViewModel, TurnProgress>(
      selector: (_, viewModel) => viewModel.progress,
      builder: (context, progress, _) {
        if (!progress.active) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final muted = theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Icon(iconFor(progress.kind),
                  size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  progress.activity.isEmpty ? 'working' : progress.activity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(counters(progress), style: muted),
            ],
          ),
        );
      },
    );
  }

  /// The icon that matches the activity. One icon, no generic spinner: a
  /// spinning circle says "something is happening", this says what.
  static IconData iconFor(ActivityKind kind) {
    switch (kind) {
      case ActivityKind.thinking:
        return Icons.psychology; // brain
      case ActivityKind.writing:
        return Icons.draw; // pad and pen
      case ActivityKind.reading:
        return Icons.menu_book;
      case ActivityKind.editingFile:
        return Icons.edit_note;
      case ActivityKind.runningCommand:
        return Icons.terminal;
      case ActivityKind.searching:
        return Icons.search;
      case ActivityKind.browsing:
        return Icons.public;
      case ActivityKind.callingTool:
      case ActivityKind.tool:
        return Icons.build;
      case ActivityKind.waiting:
        return Icons.hourglass_top;
      case ActivityKind.idle:
        return Icons.autorenew;
    }
  }

  /// `85 tok/s`
  ///
  /// Generation speed, and nothing else. The earlier line reported tokens out,
  /// context used, tool output and context percentage; those were read from
  /// figures the backend does not report reliably, so a run could show numbers
  /// that were not describing it. Speed is the one figure that can be measured
  /// from Pi's own timings, so it is the one worth putting in front of someone.
  static String counters(TurnProgress progress) {
    final rate = progress.tokensPerSecond;
    // Nothing to divide by yet: the request is sent, the model has not started.
    if (rate <= 0) return 'starting…';
    // One decimal only while the number is small enough that the difference
    // matters; a whole number is easier to read at any real speed.
    return '${rate.toStringAsFixed(rate < 10 ? 1 : 0)} tok/s';
  }
}
