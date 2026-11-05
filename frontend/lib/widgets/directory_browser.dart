import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pi_models.dart';
import '../providers/pi_view_model.dart';

/// Bottom-sheet content for browsing the filesystem and setting the Pi
/// working directory. Changing the directory restarts Pi with a fresh session.
class DirectoryBrowser extends StatefulWidget {
  const DirectoryBrowser({Key? key}) : super(key: key);

  @override
  State<DirectoryBrowser> createState() => _DirectoryBrowserState();
}

class _DirectoryBrowserState extends State<DirectoryBrowser> {
  DirListing? _listing;
  bool _loading = true;
  bool _applying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Not straight away: this sheet is mounted while the framework is building,
    // and the first thing _browse does is tell the view model it is loading -
    // which marks the provider above this widget dirty in the middle of a build.
    // The listing is fetched once the frame that put this sheet on screen is
    // finished, which is also when there is a spinner worth showing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _browse(null));
  }

  Future<void> _browse(String? path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final vm = context.read<PiViewModel>();
    final listing = await vm.browseDirectory(path: path);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (listing != null) {
        _listing = listing;
      } else {
        _error = vm.error ?? 'Could not list that directory.';
      }
    });
  }

  Future<void> _setWorkingDirectory(String path) async {
    setState(() => _applying = true);
    final vm = context.read<PiViewModel>();
    final ok = await vm.setWorkingDirectory(path);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _applying = false;
        _error = vm.error ?? 'Could not change the working directory.';
      });
    }
  }

  String _dirName(String path) {
    final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
    final segments = trimmed.split(RegExp(r'[\\/]'));
    return segments.isEmpty ? trimmed : segments.last;
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.folder_open),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Working directory',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_loading || _applying)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: () => _browse(listing?.path),
                ),
            ],
          ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: Colors.red.shade100,
            padding: const EdgeInsets.all(10),
            child: Text(
              _error!,
              style: TextStyle(color: Colors.red.shade900, fontSize: 13),
            ),
          ),
        if (listing != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Browsing: ${listing.path}',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (listing.parent != null)
                  TextButton.icon(
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    label: const Text('Up'),
                    onPressed: () => _browse(listing.parent),
                  ),
              ],
            ),
          ),
          if (listing.roots.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final root in listing.roots)
                    ActionChip(
                      avatar: Icon(Icons.storage, size: 16),
                      label: Text(root.name),
                      onPressed: listing.path == root.path
                          ? null
                          : () => _browse(root.path),
                    ),
                ],
              ),
            ),
          ],
          if (listing.recent.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text('Recent',
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 90),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final recent in listing.recent)
                        ActionChip(
                          avatar: const Icon(Icons.history, size: 16),
                          label: Text(_dirName(recent)),
                          onPressed: listing.path == recent
                              ? null
                              : () => _browse(recent),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const Divider(height: 1),
          Expanded(
            child: listing.entries.isEmpty
                ? Center(
                    child: Text('No subdirectories here.',
                        style: Theme.of(context).textTheme.bodyMedium),
                  )
                : ListView.separated(
                    itemCount: listing.entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final entry = listing.entries[index];
                      return ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(entry.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _browse(entry.path),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(
                    _applying
                        ? 'Switching...'
                        : 'Set as working directory (${listing.path})',
                  ),
                  onPressed: _applying
                      ? null
                      : () => _setWorkingDirectory(listing.path),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
