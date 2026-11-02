import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pi_models.dart';
import '../providers/pi_view_model.dart';

/// The git branch, and the state behind it, at the right end of the app bar.
///
/// It lives in the bar's actions rather than in its title. The title box is
/// width-limited by the AppBar itself, so the most a flex inside it can do is
/// fill that box - which is how a branch came to sit in the middle of a wide
/// window with half the bar empty behind it. The actions are what the bar
/// actually right-aligns, and this belongs with the other things that are read
/// rather than pressed.
///
/// The branch name is what fits; whether the tree is dirty, mid-conflict, or
/// unpushed is in the tooltip, because that is a sentence and the bar has no
/// room for one.
class GitStatusChip extends StatelessWidget {
  const GitStatusChip({super.key});

  /// A long branch name is shortened rather than allowed to push the context
  /// percentage out of the bar. Branch names people choose fit well inside this;
  /// the tooltip carries the name in full either way.
  static const double _maxBranchWidth = 140;

  @override
  Widget build(BuildContext context) {
    return Selector<PiViewModel, (String?, GitStatus?)>(
      // The pair, not just the name: the counts behind the tooltip change while
      // the branch stays the same, and a tooltip that keeps describing an older
      // working tree is worse than no tooltip.
      selector: (_, viewModel) => (viewModel.gitBranch, viewModel.gitStatus),
      builder: (context, selected, _) {
        final (branchName, git) = selected;
        if (branchName == null || branchName.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Tooltip(
            message: git?.describe() ?? branchName,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.merge_type,
                  size: 16,
                  // A conflict is the one state the colour should say on its
                  // own: unlike "dirty", it blocks the next commit.
                  color: (git?.conflicted ?? 0) > 0
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxBranchWidth),
                  child: Text(
                    branchName,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
