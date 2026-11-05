import 'package:flutter/material.dart';

import '../models/pi_models.dart';
import '../providers/pi_view_model.dart';

/// The dialog that names a saved session, by typing it or by asking the model.
///
/// A widget rather than a `showDialog(builder: ...)` because it holds a
/// [TextEditingController]: a controller disposed by the code that opened the
/// dialog is gone before the dialog has finished animating out, and the field
/// rebuilds while it is still going. Owning it here means it is disposed when
/// this state is, which is when the field stops existing.
///
/// The suggestion goes into the field rather than straight onto the session: what
/// a model guesses about a conversation is worth reading before it becomes that
/// conversation's label, and the typed name is the one that gets kept.
class SessionRenameDialog extends StatefulWidget {
  final PiSessionInfo session;
  final PiViewModel viewModel;

  const SessionRenameDialog({
    super.key,
    required this.session,
    required this.viewModel,
  });

  @override
  State<SessionRenameDialog> createState() => _SessionRenameDialogState();
}

class _SessionRenameDialogState extends State<SessionRenameDialog> {
  late final TextEditingController _controller;

  /// A model call is in flight. The button is closed while it runs so a second
  /// tap cannot start a second one behind the first.
  bool _suggesting = false;

  /// Why the last suggestion failed, shown next to the field it failed into.
  String? _suggestionError;

  PiSessionInfo get _session => widget.session;
  PiViewModel get _viewModel => widget.viewModel;

  String get _currentName => _session.name?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String? name) async {
    final ok = await _viewModel.renameSession(_session, name);
    // Only close over a rename that happened. A sheet still showing the old name
    // is the person's chance to read the error and try again.
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _suggest() async {
    setState(() {
      _suggesting = true;
      _suggestionError = null;
    });
    final title = await _viewModel.suggestSessionTitle(_session);
    if (!mounted) return;
    setState(() => _suggesting = false);
    // A failed suggestion leaves the text that was already in the field alone.
    if (title != null) _controller.text = title;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_currentName.isEmpty
          ? 'Name this session'
          : 'Rename “$_currentName”'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 120,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Name',
              helperText:
                  'Shown in the session list instead of the first message',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (text) => _save(text),
          ),
          if (_suggestionError != null) ...[
            const SizedBox(height: 8),
            Text(
              _suggestionError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _suggesting ? null : _suggest,
              icon: _suggesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _suggesting ? 'Asking the model…' : 'Suggest a name',
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        // Only offered for a session that has a name to take away. Clearing is
        // sending no name, which is what Pi's own /name does with an empty one.
        if (_currentName.isNotEmpty)
          TextButton(
            onPressed: () => _save(null),
            child: const Text('Clear name'),
          ),
        FilledButton(
          onPressed: () => _save(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
