import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pi_models.dart';
import '../providers/pi_view_model.dart';
import '../utils/code_highlight.dart';
import 'file_viewer.dart';

/// Browse and view files in the current directory.
class FileBrowser extends StatefulWidget {
  /// Passed straight to the viewer, which is where lines get selected. The
  /// prompt field is not this widget's to write in, so the handing over goes on
  /// up to whoever opened this sheet.
  final void Function(String reference)? onUseInPrompt;

  const FileBrowser({super.key, this.onUseInPrompt});

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  FileListing? _listing;
  bool _loading = true;
  String? _error;
  String? _currentPath;
  bool _applying = false;

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
      _currentPath = path;
    });

    final vm = context.read<PiViewModel>();

    try {
      final listing = await vm.listFiles(path: path);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _listing = listing;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openFile(DirEntry entry) async {
    if (entry.isDirectory == true) {
      _browse(entry.path);
    } else {
      showDialog(
        context: context,
        builder: (context) => FileViewer(
          filePath: entry.path,
          fileName: entry.name,
          onUseInPrompt: widget.onUseInPrompt,
        ),
      );
    }
  }

  Future<void> _setWorkingDirectory() async {
    final listing = _listing;
    if (listing == null) return;

    setState(() => _applying = true);
    final vm = context.read<PiViewModel>();
    final ok = await vm.setWorkingDirectory(listing.path);
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

  Future<void> _showCreateFolderDialog() async {
    final listing = _listing;
    if (listing == null || _loading) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Folder name',
            hintText: 'Create inside ${listing.path}',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;

    setState(() => _loading = true);
    final vm = context.read<PiViewModel>();
    final created = await vm.createDirectory(name: trimmed, path: listing.path);
    if (!mounted) return;
    if (created == null) {
      setState(() {
        _loading = false;
        _error = vm.error ?? 'Could not create folder.';
      });
    } else {
      // Refresh the current listing so the new folder appears.
      _browse(listing.path);
    }
  }

  String _dirName(String path) {
    final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
    final segments = trimmed.split(RegExp(r'[\\/]'));
    return segments.isEmpty ? trimmed : segments.last;
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(DirEntry entry) {
    if (entry.isDirectory == true) return Icons.folder;

    // Same detection the viewer colours with, so the icon in the list and the
    // colouring in the viewer cannot disagree about what a file is.
    final language = languageForPath(entry.path);
    switch (language) {
      case 'javascript':
      case 'typescript':
      case 'dart':
      case 'python':
      case 'go':
      case 'rust':
      case 'java':
      case 'csharp':
      case 'c++':
      case 'php':
      case 'ruby':
      case 'shell':
        return Icons.code;
      case 'json':
      case 'yaml':
      case 'ini':
      case 'properties':
        return Icons.data_object;
      case 'xml':
        return Icons.language;
      case 'css':
        return Icons.palette;
      case 'sql':
        return Icons.storage;
      case 'dockerfile':
      case 'makefile':
        return Icons.settings;
      case 'diff':
        return Icons.compare;
      default:
        break;
    }

    final name = entry.name.toLowerCase();
    if (name.endsWith('.txt') ||
        name.endsWith('.md') ||
        name.endsWith('.log')) {
      return Icons.description;
    }
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp') ||
        name.endsWith('.svg')) {
      return Icons.image;
    }

    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.folder_open),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'File Browser',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_loading || _applying)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.create_new_folder),
                    tooltip: 'New folder',
                    onPressed: listing == null ? null : _showCreateFolderDialog,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: () => _browse(_currentPath),
                  ),
                ],
              ],
            ),
          ),

          // Error message
          if (_error != null)
            Container(
              width: double.infinity,
              // The theme's own error pair, so this reads in light and in dark
              // instead of being a pale block that only makes sense on one.
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(10),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontSize: 13,
                ),
              ),
            ),

          // Action buttons for current directory
          if (listing != null && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(
                    _applying ? 'Switching...' : 'Set as working directory',
                  ),
                  onPressed: _applying ? null : _setWorkingDirectory,
                ),
              ),
            ),

          // Current path
          if (listing != null && !_loading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Location: ${listing.path}',
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

            // Roots (drives on Windows, / on Unix)
            if (listing.roots.isNotEmpty) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final root in listing.roots)
                      ActionChip(
                        avatar: const Icon(Icons.storage, size: 16),
                        label: Text(root.name),
                        onPressed: listing.path == root.path
                            ? null
                            : () => _browse(root.path),
                      ),
                  ],
                ),
              ),
            ],

            // Recent directories
            if (listing.recent.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recent',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              SizedBox(
                height: 45,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: listing.recent.length,
                  itemBuilder: (context, index) {
                    final recent = listing.recent[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.history, size: 16),
                        label: Text(_dirName(recent)),
                        onPressed: listing.path == recent
                            ? null
                            : () => _browse(recent),
                      ),
                    );
                  },
                ),
              ),
            ],

            const Divider(height: 1),

            // Files and folders list
            if (listing.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'This directory is empty',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: listing.entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = listing.entries[index];
                    final isDir = entry.isDirectory == true;

                    return ListTile(
                      leading: Icon(
                        _getFileIcon(entry),
                        size: 20,
                      ),
                      title: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle:
                          isDir ? null : Text(_formatFileSize(entry.size)),
                      trailing: Icon(
                        isDir ? Icons.chevron_right : Icons.open_in_new,
                        size: 18,
                      ),
                      onTap: () => _openFile(entry),
                    );
                  },
                ),
              ),
          ],

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
