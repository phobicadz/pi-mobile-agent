import 'package:flutter/material.dart';

import '../models/pi_models.dart';
import '../providers/pi_view_model.dart';

/// The picker that clones one of the user's GitHub repositories into a directory.
///
/// It lists the repositories rather than asking for a URL because the thing a
/// person has is a name they half-remember ("the docker configs one"), and the
/// list is what turns that into a tap. Typing is still the way to narrow a list
/// of dozens, and a text that is not in the list is still offered as a clone —
/// which is what makes a repository owned by someone else, or one past the
/// backend's listing cap, reachable from the same field.
///
/// [intoPath] is the directory the file browser is showing, not the directory Pi
/// happens to be in. The two are usually the same, and when they are not, the
/// one you are looking at is the one a clone belongs in — so it is said out loud
/// above the list rather than assumed.
class GitHubCloneDialog extends StatefulWidget {
  final PiViewModel viewModel;
  final String intoPath;

  const GitHubCloneDialog({
    super.key,
    required this.viewModel,
    required this.intoPath,
  });

  @override
  State<GitHubCloneDialog> createState() => _GitHubCloneDialogState();
}

class _GitHubCloneDialogState extends State<GitHubCloneDialog> {
  final _controller = TextEditingController();

  List<GitHubRepo>? _repos;
  bool _loading = true;
  String? _error;

  /// The repository being cloned right now. One at a time: two clones into the
  /// same directory are a race over the same folder name.
  String? _cloning;

  PiViewModel get _viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    // After the frame, for the reason the file browser gives: asking the view
    // model to start loading marks the provider above this dialog dirty while
    // the framework is still building it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final repos = await _viewModel.listGitHubRepos();
    if (!mounted) return;

    setState(() {
      _loading = false;
      _repos = repos;
      if (repos == null) {
        _error = _viewModel.error ?? 'Could not read your GitHub repositories.';
      }
    });
  }

  Future<void> _clone(String repo) async {
    setState(() => _cloning = repo);

    final path = await _viewModel.cloneGitHubRepo(
      repo: repo,
      path: widget.intoPath,
    );

    if (!mounted) return;
    setState(() => _cloning = null);

    // Only close over a clone that happened. A dialog that closed on a failure
    // would take the reason with it and leave a directory that is not there.
    if (path != null && path.isNotEmpty) {
      Navigator.of(context).pop(path);
      return;
    }

    setState(
      () => _error = _viewModel.error ?? 'Could not clone $repo.',
    );
  }

  /// The `owner/name` a typed text means, or null when it is a search word.
  ///
  /// A copy of what the backend accepts, and deliberately not the authority: the
  /// backend validates every clone request whatever this decides. It is here to
  /// know when a field holds a repository someone meant to name — a pasted URL,
  /// a `git@github.com:…` string — rather than a word to filter by.
  String? _typedSlug() {
    var text = _query.trim().replaceAll(RegExp(r'/+$'), '');
    if (text.isEmpty) return null;

    text = text.replaceAllMapped(
      RegExp(r'^(https?://)?(www\.)?github\.com/', caseSensitive: false),
      (_) => '',
    );
    text = text.replaceAll(
      RegExp(r'^ssh://git@github\.com/?', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'^git@github\.com:?/?', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'\.git$', caseSensitive: false), '');

    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$')
            .hasMatch(text)
        ? text
        : null;
  }

  String get _query => _controller.text;

  List<GitHubRepo> get _reposOrNull => _repos ?? const [];

  /// One repository in the list: what it is, whether it is private, and the tap
  /// that starts the clone.
  Widget _repoRow(GitHubRepo repo) {
    final isThisOne = _cloning == repo.slug;
    return ListTile(
      // A private repository is the one a clone can fail on permissions for, so
      // the difference is worth showing before the tap rather than learning it
      // from the error afterwards.
      leading: Icon(
        repo.isPrivate ? Icons.lock : Icons.lock_open,
        size: 20,
      ),
      title: Text(repo.slug, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: repo.description == null
          ? null
          : Text(
              repo.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: isThisOne
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download, size: 18),
      // Closed while one clone is running: a second tap would ask for a second
      // clone into the same parent directory.
      onTap: _cloning == null ? () => _clone(repo.slug) : null,
    );
  }

  /// The repositories the text in the field points at, in the order the backend
  /// listed them (most recently pushed first).
  List<GitHubRepo> _matching() {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _reposOrNull;

    final slug = _typedSlug()?.toLowerCase();
    return _reposOrNull
        .where((repo) =>
            repo.slug.toLowerCase().contains(query) ||
            (slug != null && repo.slug.toLowerCase() == slug) ||
            (repo.description ?? '').toLowerCase().contains(query))
        .toList();
  }

  /// Whether the text in the field should be offered as a clone in its own right.
  ///
  /// Yes for anything typed that the list is not already offering: a repository
  /// belonging to someone else, one past the listing cap, or a name spelled from
  /// memory. No when a row on the screen already *is* that repository — text
  /// typed well enough to narrow the list to one thing needs that row, not a
  /// second control with the same effect, which is what the picker would
  /// otherwise grow every time the field works.
  bool get _offerTypedText {
    final typed = _query.trim().toLowerCase();
    if (typed.isEmpty) return false;
    return !_matching().any(
      (repo) =>
          repo.slug.toLowerCase() == typed || repo.name.toLowerCase() == typed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = _matching();
    final typed = _query.trim();

    return Dialog(
      // A plain [Dialog] and not an [AlertDialog]: AlertDialog sizes itself with
      // [IntrinsicWidth], and a list of search results is exactly the thing that
      // cannot answer a question about its own intrinsic size. The one sheet in
      // this app that is worth listing dozens of things in is this one.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Clone from GitHub', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'into ${widget.intoPath}',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search your repositories',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  // The same thing a tap on the row it narrowed to would do.
                  if (_offerTypedText) {
                    _clone(typed);
                  } else if (matches.length == 1) {
                    _clone(matches.first.slug);
                  }
                },
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ),
              ],

              if (_cloning != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      // A clone of a real repository takes minutes, and the wait
                      // is worth sitting through when you can see which one it is.
                      child: Text(
                        'Cloning $_cloning…',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else ...[
                if (_offerTypedText)
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: Text('Clone $typed'),
                    subtitle:
                        const Text('not in your list — clone it as typed'),
                    onTap: _cloning == null ? () => _clone(typed) : null,
                  ),
                if (matches.isEmpty && !_offerTypedText)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      typed.isEmpty
                          ? 'No repositories found.'
                          : 'No match for “$typed”.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),

                // A Column rather than a ListView: this whole sheet already
                // scrolls, and a second viewport inside it is a second thing to
                // fight over a drag. The backend caps what it lists, so the cost
                // of building these rows is bounded by a number, not by an
                // account with thousands of repositories.
                for (var i = 0; i < matches.length; i++) ...[
                  _repoRow(matches[i]),
                  if (i != matches.length - 1) const Divider(height: 1),
                ],
              ],

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
