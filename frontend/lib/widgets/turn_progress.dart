import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/turn_progress.dart';
import '../providers/pi_view_model.dart';
import '../utils/format.dart';

/// One-line status strip shown while Pi is working: what it is doing right now
/// (`thinking`, `read package.json`, `bash npm test`) and how many tokens that
/// has cost so far, so a long tool run is visibly progressing instead of
/// looking frozen.
///
/// Rebuilds only when a value in [PiViewModel.progress] actually changes -
/// Pi's stream frames are coalesced in the view model, and the selected
/// [TurnProgress] has value equality, so this is not rebuilt per token.
class TurnProgressBar extends StatelessWidget {
  const TurnProgressBar({super.key});

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
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
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
              Text(_counters(progress), style: muted),
            ],
          ),
        );
      },
    );
  }

  /// `1.2k tok out · 34k ctx · 12.4k chars · 30%`
  ///
  /// Counters are only added when they carry information: an estimate is marked
  /// with `~` so it is never mistaken for a provider-reported number, and tool
  /// output appears only once a tool has actually produced some.
  static String _counters(TurnProgress progress) {
    final parts = <String>[];
    final produced = progress.producedTokens;
    if (produced > 0) {
      parts.add(
        '${progress.estimated ? '~' : ''}${formatTokens(produced)} tok out',
      );
    }
    final consumed = progress.consumedTokens;
    if (consumed > 0) parts.add('${formatTokens(consumed)} ctx');
    if (progress.toolOutputChars > 0) {
      parts.add('${formatCount(progress.toolOutputChars)} chars');
    }
    final percent = progress.contextPercent;
    if (percent != null && percent > 0) parts.add('${percent.round()}%');
    if (parts.isEmpty) return 'starting…';
    return parts.join(' · ');
  }
}
