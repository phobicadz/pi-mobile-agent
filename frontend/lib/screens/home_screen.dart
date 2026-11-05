import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/pi_models.dart';
import '../providers/appearance_controller.dart';
import '../providers/pi_view_model.dart';
import '../utils/notification_store.dart';
import '../utils/prompt_reference.dart';
import '../utils/responsive.dart';
import '../widgets/attachment_tray.dart';
import '../widgets/chat_list.dart';
import '../widgets/context_meter.dart';
import '../widgets/file_browser.dart';
import '../widgets/git_status_chip.dart';
import '../widgets/model_selector.dart';
import '../widgets/session_rename_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _chatKey = GlobalKey<ChatListState>();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  /// Set when a send on a physical keyboard takes focus away, so the field gets
  /// it back when the run ends rather than on every idle rebuild. Cleared once.
  /// Never set on a touch platform, where focus would mean an on-screen
  /// keyboard landing over the reply that just finished.
  bool _refocusAfterRun = false;

  /// Whether to say so when a run this screen started comes to an end.
  ///
  /// On by default: the reason a long task is worth starting on a phone is that
  /// you can put the phone down and come back, and that only works if something
  /// tells you the answer is there. The toggle exists because the same notice is
  /// noise while you are watching the reply stream in.
  ///
  /// Held here rather than in a controller of its own: this screen is the only
  /// thing that both shows the notice and offers the switch. The appearance
  /// settings are a provider because `MaterialApp` has to be built with them;
  /// a notice has no such requirement, and a provider above the whole app for
  /// one switch is a dependency the tree does not need.
  bool _notificationsEnabled = true;

  /// A prompt this screen sent is still running.
  ///
  /// The notice is armed by sending, not by watching the busy flag flip: a run
  /// can end without the user asking for one (a reconnect settling the state,
  /// a session being restored) and those are not things to announce.
  bool _awaitingRunEnd = false;

  /// The view model this State is listening to, so the listener can be detached
  /// from the same instance it was attached to.
  PiViewModel? _observed;

  /// Whether this is a context with a physical keyboard: a desktop, or a desktop
  /// browser (on the web `defaultTargetPlatform` reports the browser's OS).
  ///
  /// Two things depend on it, and they depend on it for the same reason - on a
  /// touch platform focus *is* the on-screen keyboard, so giving focus away is
  /// not a neutral act there.
  static bool get _physicalKeyboardExpected => const {
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    if (_physicalKeyboardExpected) {
      // A Focus/Shortcuts wrapper would only work while something inside the
      // app holds focus, and the prompt field swallows PageUp/PageDown as text
      // navigation - the chat would scroll some of the time and not others.
      // A keyboard handler makes the two keys mean the same thing everywhere.
      HardwareKeyboard.instance.addHandler(_scrollChatWithPageKeys);
    }
    unawaited(_restoreNotificationPreference());
  }

  /// Read back whatever this browser stored, before the first run ends, so a
  /// phone that was silenced yesterday is still silenced today.
  Future<void> _restoreNotificationPreference() async {
    final stored = await loadNotificationsEnabled();
    if (stored == null || !mounted) return;
    setState(() => _notificationsEnabled = stored);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribed rather than watched in `build`: the view model notifies for
    // every streamed token, and a `watch` here would rebuild the whole screen -
    // bar, composer and all - at that rate. The chat list goes to some trouble
    // to avoid exactly that; this screen should not reintroduce it from the top.
    final viewModel = context.read<PiViewModel>();
    if (identical(viewModel, _observed)) return;
    _observed?.removeListener(_onViewModelChanged);
    _observed = viewModel;
    viewModel.addListener(_onViewModelChanged);
  }

  /// Notice the run this screen asked for coming to an end.
  ///
  /// Fires on the view model's own update, which is not necessarily between
  /// frames, so the notice is deferred to the frame after: the chat has to have
  /// taken the reply in before something points at it.
  void _onViewModelChanged() {
    final viewModel = _observed;
    if (viewModel == null || !_awaitingRunEnd) return;
    if (viewModel.isLoading) return;

    _awaitingRunEnd = false;
    if (!_notificationsEnabled) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // Floating rather than full-width: the notice is about the reply above
          // it, and a bar stapled to the bottom of the screen covers the send
          // field, which is where the next prompt is being typed.
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          content: const Text('Agent finished'),
        ),
      );
    });
  }

  /// Scrolls the chat a viewport per press. Handing the key back as unhandled
  /// when the chat cannot move keeps the browser's own paging behaviour.
  bool _scrollChatWithPageKeys(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final forward = event.logicalKey == LogicalKeyboardKey.pageDown;
    if (!forward && event.logicalKey != LogicalKeyboardKey.pageUp) return false;
    // While the sessions sheet or the folder browser is open, the chat behind it
    // must not move.
    if (!(ModalRoute.of(context)?.isActive ?? true)) return false;
    return _chatKey.currentState?.scrollByPage(forward: forward) ?? false;
  }

  void _sendPrompt(PiViewModel viewModel) {
    if (viewModel.isLoading || _inputController.text.trim().isEmpty) return;
    viewModel.submitPrompt(_inputController.text);
    _inputController.clear();
    viewModel.setUserInput('');
    // Tapping the send button already dismissed the on-screen keyboard, because
    // focus went to the button. Enter never got the same treatment: the field
    // kept focus, so the keyboard stayed up over the reply the user had just
    // sent. On a touch platform releasing focus *is* hiding the keyboard, which
    // is what the two buttons should mean. On a physical keyboard there is no
    // keyboard to hide, and holding focus is what lets the next prompt be typed
    // while the agent is still working - so there the field keeps focus and the
    // run that ends asks for it back.
    if (_physicalKeyboardExpected) {
      _refocusAfterRun = true;
    } else {
      _inputFocus.unfocus();
    }
    // Arm the notice for this run. Set here rather than inferred from the busy
    // flag going true, so a run the app did not start is never announced.
    _awaitingRunEnd = true;
    _chatKey.currentState?.stickToBottom();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_scrollChatWithPageKeys);
    _observed?.removeListener(_onViewModelChanged);
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// The busy state for loading a saved conversation back into the live session.
  ///
  /// A panel over the chat rather than a spinner in a corner: restoring a session
  /// reads every saved `.jsonl` in the archive and then hands the history back,
  /// which is seconds of doing nothing visible on a phone. The chat behind it is
  /// the thing that is about to change, so that is what carries the notice.
  Widget _resumeOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Positioned.fill(
      child: ColoredBox(
        color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.62),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Restoring session…',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSessionPicker(BuildContext context) async {
    final viewModel = context.read<PiViewModel>();
    // Fetch fresh before opening the sheet; the sheet can refresh too.
    await viewModel.loadSessions();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Consumer<PiViewModel>(
          builder: (context, vm, _) {
            final sessions = vm.sessions;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.history),
                      const SizedBox(width: 8),
                      Text('Resume a session',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      if (vm.loadingSessions)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh',
                          onPressed: () => vm.loadSessions(),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: sessions.isEmpty
                      ? Center(
                          child: Text(
                            vm.loadingSessions
                                ? 'Loading sessions...'
                                : 'No saved sessions found.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: sessions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final session = sessions[index];
                            // The conversation being had. Its file is open and still
                            // being appended to, so deleting it would leave an app
                            // sitting in a conversation that no longer exists - the row
                            // says so instead of the backend throwing at it.
                            final isLive = vm.liveSessionPath != null &&
                                vm.liveSessionPath == session.path;
                            
                            // Distinguish between a set name and the session's content
                            final hasName = session.name != null && session.name!.isNotEmpty;
                            final title = hasName
                                ? session.name!
                                : (session.preview.isNotEmpty
                                    ? session.preview
                                    : '(empty session)');
                            
                            return ListTile(
                              leading: const Icon(Icons.chat_bubble_outline),
                              title: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: hasName
                                    ? null
                                    : Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          fontStyle: FontStyle.italic,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                              ),
                              subtitle: Text(
                                '${session.messageCount} messages  •  '
                                '${_formatAge(session.modified)}  •  ${session.cwd}'
                                '${!hasName && session.preview.isNotEmpty ? '  •  (No session name set)' : ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () async {
                                Navigator.of(sheetContext).pop();
                                await vm.resumeSession(session.path);
                              },
                              // Renaming lives on the row rather than inside the
                              // conversation: a name is about finding a session,
                              // and this is the list that is searched by name.
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Rename',
                                    onPressed: () => _showRenameSessionDialog(
                                      sheetContext,
                                      vm,
                                      session,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: isLive
                                        ? 'This is the session you are in'
                                        : 'Delete',
                                    // Red, and only where it can be pressed: the
                                    // colour is saying "this one can be thrown
                                    // away", and painting the one that cannot be
                                    // red as well would make the colour mean
                                    // nothing. colorScheme.error rather than a red,
                                    // so it is the same red the rest of the app uses
                                    // for a thing that can cost you something.
                                    color: isLive
                                        ? null
                                        : Theme.of(context).colorScheme.error,
                                    onPressed: isLive
                                        ? null
                                        : () => _confirmDeleteSession(
                                            sheetContext,
                                            vm,
                                            session,
                                          ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Open the dialog that names a saved session.
  ///
  /// The dialog is a widget of its own (see `SessionRenameDialog`) because it
  /// holds a text controller, and a controller disposed by whoever opened the
  /// dialog is gone before the dialog has finished animating out.
  Future<void> _showRenameSessionDialog(
    BuildContext context,
    PiViewModel viewModel,
    PiSessionInfo session,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => SessionRenameDialog(session: session, viewModel: viewModel),
    );
  }

  /// Ask before a session is deleted, then delete it.
  ///
  /// The confirmation is the whole point: this removes a conversation, not a
  /// listing of one, and the only thing that says whether the file was trashed or
  /// unlinked is the backend's answer. Deleting the session the app is sitting in
  /// is refused on the row, so it never reaches here.
  Future<void> _confirmDeleteSession(
    BuildContext context,
    PiViewModel viewModel,
    PiSessionInfo session,
  ) async {
    final hasName = session.name?.trim().isNotEmpty == true;
    final title = hasName
        ? session.name!.trim()
        : (session.preview.isNotEmpty ? session.preview : '(empty session)');

    final deleted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this session?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontStyle: !hasName ? FontStyle.italic : null,
                        color: !hasName 
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : null,
                      ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!hasName && session.preview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '(No session name set)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${session.messageCount} messages in '
              '${session.cwd.isEmpty ? 'an unknown directory' : session.cwd}.\n\n'
              'The conversation goes with it. Where the machine has a trash '
              'command the file is trashed rather than erased, which is the same '
              'way the Pi session picker removes one.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (deleted != true) return;
    await viewModel.deleteSession(session);
  }

  static String _formatAge(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return time.toLocal().toString().split(' ').first;
  }

  /// Start a fresh chat in the directory Pi is already working in. Nothing is
  /// deleted: the conversation being left behind is still listed under
  /// "Resume a previous session".
  Future<void> _startNewSession(BuildContext context) async {
    await context.read<PiViewModel>().startNewSession();
    _inputController.clear();
    _chatKey.currentState?.stickToBottom();
  }

  void _showFileBrowser(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.8,
        child: FileBrowser(
          onUseInPrompt: (reference) =>
              _useReferenceInPrompt(sheetContext, reference),
        ),
      ),
    );
  }

  /// Put a `path:line` reference from the file viewer into the prompt field.
  ///
  /// Copying one out and pasting it back is three steps on a phone, and the
  /// field is not visible while the browser sheet is over it - so a reference
  /// the user cannot see is one they have to trust. This closes the sheet and
  /// focuses the field instead, which is where the sentence was being written
  /// before the file was opened.
  void _useReferenceInPrompt(BuildContext sheetContext, String reference) {
    final existing = _inputController.value;
    final inserted = insertReferenceIntoPrompt(
      text: existing.text,
      selection: existing.selection.isValid
          ? existing.selection
          : TextSelection.collapsed(offset: existing.text.length),
      reference: reference,
    );

    _inputController.value = TextEditingValue(
      text: inserted.text,
      selection: TextSelection.collapsed(offset: inserted.caret),
    );
    // Setting `.value` does not go through `onChanged`, and the view model keeps
    // the draft prompt for its own reasons - a draft lost on a session switch is
    // the user's typing thrown away.
    if (mounted) context.read<PiViewModel>().setUserInput(inserted.text);

    if (sheetContext.mounted && Navigator.of(sheetContext).canPop()) {
      Navigator.of(sheetContext).pop();
    }
    _inputFocus.requestFocus();
  }

  /// The menu the hamburger opens.
  ///
  /// Every control the app bar used to carry is here instead, where each one has
  /// room to say what it does and what it is currently set to. Six icon buttons
  /// in a bar on a phone were six guesses with the explanation hidden behind a
  /// long press; a menu can spell them out.
  ///
  /// The actions run against this State's own context, not the tile's: closing
  /// the drawer takes the tile out of the tree, and the sheet each action opens
  /// needs a context that is still there.
  Widget _buildDrawer() {
    return Consumer2<PiViewModel, AppearanceController>(
      builder: (_, viewModel, appearance, __) {
        final theme = Theme.of(context);
        // Read from the theme rather than the platform: under ThemeMode.system
        // the two agree, but once a choice has been made the platform still
        // reports what the phone is set to, which is not what is on the screen.
        final showingDark = theme.brightness == Brightness.dark;
        final directory = viewModel.workingDirectoryDisplay ??
            viewModel.workingDirectory ??
            '';
        // Said in full: the bar shortened a path because it had no room for one,
        // and this menu has. Which directory a session works in is not something
        // to guess at from the last two segments of it.
        final directoryLabel = directory;

        void closeMenu() => Navigator.of(context).pop();

        return Drawer(
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.smart_toy,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text('Pi Agent',
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurface)),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: viewModel.isConnected
                                  ? Colors.green
                                  : Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            viewModel.isConnected
                                ? 'Connected'
                                : 'Disconnected',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      if (directoryLabel.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            directoryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('New session'),
                  subtitle: Text(directoryLabel.isEmpty
                      ? 'Start a fresh chat'
                      : 'Start a fresh chat in $directoryLabel'),
                  enabled: !viewModel.isLoading,
                  onTap: viewModel.isLoading
                      ? null
                      : () {
                          closeMenu();
                          _startNewSession(context);
                        },
                ),
                // No "Resume a previous session" row either, for the same reason as
                // the directory row above: the centre of the bar is the conversation -
                // its name when it has one, and the way to the list of them when it
                // does not - and that is one tap from the chat it would replace.
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Appearance',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                ListTile(
                  // The icon shows what is on the screen, because that is the
                  // only thing this control can truthfully act on: it moves away
                  // from whatever is currently being rendered.
                  leading:
                      Icon(showingDark ? Icons.light_mode : Icons.dark_mode),
                  title: Text(showingDark
                      ? 'Switch to light mode'
                      : 'Switch to dark mode'),
                  // Left open on purpose: the colours change behind the menu, so
                  // the effect is visible while the other appearance settings are
                  // still being chosen.
                  onTap: () => appearance.toggleTheme(theme.brightness),
                ),
                ListTile(
                  leading: const Icon(Icons.text_fields),
                  title: const Text('Chat text size'),
                  subtitle: Text(
                      '${(appearance.fontScale * 100).round()}% of the size the chat was designed at'),
                  // Text size for the chat only; the menu and the rest of the
                  // interface keep their own sizes.
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.text_decrease),
                        tooltip: appearance.canDecreaseFont
                            ? 'Smaller chat text'
                            : 'This is the smallest chat text',
                        onPressed: appearance.canDecreaseFont
                            ? () => appearance.changeFont(larger: false)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.text_increase),
                        tooltip: appearance.canIncreaseFont
                            ? 'Larger chat text'
                            : 'This is the largest chat text',
                        onPressed: appearance.canIncreaseFont
                            ? () => appearance.changeFont(larger: true)
                            : null,
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Notifications',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                ListTile(
                  // The icon is the state the switch is in, so the row can be
                  // read at a glance before anything is pressed.
                  leading: Icon(_notificationsEnabled
                      ? Icons.notifications_active
                      : Icons.notifications_off),
                  title: Text(_notificationsEnabled
                      ? 'Notify me when the agent finishes'
                      : 'No notice when the agent finishes'),
                  // Said plainly what turning it off costs, because the notice is
                  // the thing that makes a long task worth starting away from the
                  // keyboard.
                  subtitle: Text(_notificationsEnabled
                      ? 'A short notice in the chat when a run ends'
                      : 'You will have to watch the chat to see when a run ends'),
                  // A Switch rather than a tap-anywhere row: this row is a
                  // setting with two states, not an action, and the switch is the
                  // part that says which one it is in.
                  trailing: Switch(
                    value: _notificationsEnabled,
                    onChanged: (enabled) {
                      setState(() => _notificationsEnabled = enabled);
                      saveNotificationsEnabled(enabled);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched here rather than read deeper in the tree: the chat has to rebuild
    // when the text size changes, and this is the widget that hands the size to
    // it. The chat list is a StatefulWidget behind a GlobalKey, so its scroll
    // position and widened messages survive the rebuild.
    final appearance = context.watch<AppearanceController>();

    return Scaffold(
      // Everything the app bar used to carry as icons is here instead: in a
      // menu, where each one can say what it does and what it is currently set
      // to, rather than being a tooltip a phone has to press to read.
      drawer: _buildDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Consumer<PiViewModel>(
          builder: (context, viewModel, _) {
            final cwd = viewModel.workingDirectory ?? '';
            // Get just the directory name (last component of the path)
            final dirName = cwd.isEmpty
                ? 'Pi Agent'
                : cwd.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).last;
            // Pi omits sessionName when the session has none, so "no name" is
            // simply nothing to show rather than a placeholder for an unnamed chat.
            final sessionName = viewModel.sessionName?.trim() ?? '';

            // Two controls in one Row with the name's box exactly in the middle
            // of it. With the two outer flexes equal - a, b, a - the middle box
            // spans [a, a+b] of (2a+b), whose centre is (a + b/2) / (2a + b) = 1/2
            // whatever the numbers are. That is why the two side flexes match, and
            // why the name's share is the smaller one: a name that has to be
            // squeezed is the one that reads as secondary.
            //
            // The name belongs in the bar because it is the other half of "where am
            // I": which directory, and which conversation in it. It is also the only
            // place the live session's name is ever visible - the picker lists saved
            // sessions, and the one being had is the one not there.
            //
            // The flex lives in this Row and each Tooltip wraps its Text directly.
            // The other way round - a Tooltip holding a Row with an Expanded in it -
            // is a layout error: the widget a Tooltip keeps in place is laid out with
            // no width constraint of its own, and a flex child inside an unconstrained
            // Row throws rather than degrading.
            final folderGroup = Row(
              children: [
                const Icon(
                  Icons.folder_open,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: cwd.isEmpty ? 'No directory selected' : cwd,
                    child: Text(
                      dirName,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            );

            // A click cursor is the only thing that says "this is a control" on a
            // laptop browser, where there is no press to find it by. The padding is
            // the tap target: on a phone the whole strip is what a thumb has to be
            // able to land on.
            final folderControl = MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(
                // Tapping it opens the same browser the menu offers as "Browse files
                // & set working directory". Which directory a run happens in is decided
                // while the chat is being read, and the folder is already on screen
                // saying it - sending the user to a hamburger to change it is a second
                // place to learn the same thing.
                onTap: () => _showFileBrowser(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 10,
                  ),
                  child: folderGroup,
                ),
              ),
            );

            // The centre of this bar is the conversation: its name when it has
            // one, and the way to the list of them when it does not. The menu used
            // to be that way, and it was a place to look for something that is only
            // ever wanted while looking at the conversation it would replace.
            //
            // Both are switched off while a session is being restored: a second
            // resume started over the first races the history being loaded into the
            // live session, which is the same reason the menu row used to close.
            void openPicker() => _showSessionPicker(context);
            final pickerEnabled = !viewModel.resumingSession;

            // The chat bubble icon that always appears before the session name.
            final sessionIcon = Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 18,
              ),
            );

            final nameControl = MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(
                // Tapping it opens the session picker. The name is the live session's,
                // and the one thing worth doing with it is leaving it - a decision made
                // while looking at the list of where else one could be.
                //
                // It is a separate control from the folder beside it on purpose: one
                // changes where the agent works, the other which conversation it is in,
                // and merging them would make the second impossible to reach without
                // guessing which one was meant.
                onTap: pickerEnabled ? openPicker : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      sessionIcon,
                      Flexible(
                        child: Tooltip(
                          message: pickerEnabled
                              ? 'Session: $sessionName — tap to switch or rename it'
                              : 'Session: $sessionName — restoring a session first',
                          child: Text(
                            sessionName,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            // Bold, and one step up from the label size the git chip uses:
                            // this is the centre of the bar and the name of the thing the
                            // rest of the screen is about, not a caption on the directory.
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );

            if (sessionName.isEmpty) {
              // No name to centre, so the centre holds the way in. An icon and no
              // words: an unnamed chat has nothing to say there, but the list is
              // still one tap away.
              //
              // Built like the folder control rather than as an IconButton, and for
              // the width that costs: an IconButton is 48px of tap target, and on a
              // phone with the git chip and the context meter in the actions this
              // box measured 37.5px end to end. An icon at the size the folder's is
              // fits where a button would overflow the bar.
              //
              // It is not a flex child, so it is laid out at its own width first and
              // the two Expandeds then split what is left equally - which puts it in
              // the middle without borrowing space the directory needs.
              final sessionsControl = MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  onTap: pickerEnabled ? openPicker : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    child: Tooltip(
                      message: pickerEnabled
                          ? 'Sessions'
                          : 'Restoring a session…',
                      child: const Icon(
                        Icons.forum_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              );

              return Row(
                children: [
                  Expanded(flex: 1, child: folderControl),
                  sessionsControl,
                  const Expanded(
                    flex: 1,
                    child: SizedBox.shrink(),
                  ),
                ],
              );
            }

            // Responsive flex ratios: on small screens, prioritize the session name
            // visibility by reducing folder width. On desktop, center it more.
            final screenWidth = MediaQuery.of(context).size.width;
            final isSmallScreen = screenWidth < ResponsiveSizes.phoneMaxWidth;
            
            final (folderFlex, nameFlex, spacerFlex) = isSmallScreen
                ? (2, 5, 2)      // Small screens: name gets more space
                : (4, 3, 4);     // Larger screens: keep the centered design
            
            return Row(
              children: [
                Expanded(flex: folderFlex, child: folderControl),
                // Centred: the box is centred, and Center puts the text in the middle
                // of a box it does not have to fill. Loose-fit, so a short name costs
                // the bar nothing and a long one ellipsizes inside its own share.
                Flexible(
                  flex: nameFlex,
                  fit: FlexFit.loose,
                  child: Center(child: nameControl),
                ),
                // The counterweight. Without an identical share on the right there is
                // no centre to put anything in.
                Expanded(
                  flex: spacerFlex,
                  child: const SizedBox.shrink(),
                ),
              ],
            );
          },
        ),
        elevation: 0,
        actions: [
          // The branch belongs here rather than in the title: the title box is
          // width-limited by the AppBar, so a flex in it can only fill that box -
          // which put the branch in the middle of a wide window with half the bar
          // empty behind it. Actions are what the bar right-aligns.
          const GitStatusChip(),
          // How full this conversation is, from Pi's own measurement. Ahead of
          // the connection dot: this is the one you act on - start a new session
          // or compact - while the dot only tells you the app is talking.
          const ContextMeter(),
          // The connection state as a dot and nothing else. It stays in the bar
          // because it is not a control: it is the one thing on this screen that
          // has to be visible without asking for it.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Selector<PiViewModel, bool>(
                selector: (_, viewModel) => viewModel.isConnected,
                builder: (context, isConnected, _) {
                  return Tooltip(
                    message: isConnected ? 'Connected' : 'Disconnected',
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isConnected ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: Consumer<PiViewModel>(
        builder: (context, viewModel, _) {
          if (!viewModel.isConnected) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Connecting to Pi Backend...',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            );
          }

          // The prompt panel's own padding, safe areas included. The bottom
          // inset is the bottom padding, not a base for adding more: on a phone
          // the browser's home-indicator band already is the gap between the
          // field and the edge of the screen, so the fixed 16 this panel used to
          // add on top of it just left an empty band under the field - 50px on a
          // notched iPhone that needs 34.
          //
          // The band is a swipe zone rather than a dead zone, so the composer
          // reaches 12px into it: the field's bottom edge stays off the very
          // bottom of the screen, where a tap would compete with the home
          // gesture, but it is not pushed a whole band above it.
          final insets = MediaQuery.of(context).padding;
          final panelPadding = ResponsiveSizes.getInputAreaPadding(
            MediaQuery.of(context).size.width,
            insets: insets,
          );

          // The body is already a Consumer, so this builder runs on every
          // change - no extra listener needed to notice the run ending. The
          // request goes after the frame so it lands on the field that the
          // rebuild produced, not one about to be replaced.
          //
          // Only ever asked for where a physical keyboard makes it free: on a
          // phone the run ending is exactly when the user came back to read the
          // reply, and asking for focus there brings the on-screen keyboard
          // straight back up over it.
          if (!viewModel.isLoading && _refocusAfterRun) {
            _refocusAfterRun = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _inputFocus.requestFocus();
            });
          }

          return Column(
            children: [
              // Error message
              if (viewModel.error != null)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ResponsiveSizes.inputAreaMaxWidth,
                    ),
                    child: Container(
                      color: Colors.red.shade100,
                      padding: const EdgeInsets.all(12),
                      margin: EdgeInsets.symmetric(
                        horizontal: ResponsiveSizes.paddingLarge,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              viewModel.error!,
                              style: TextStyle(color: Colors.red.shade900),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: Colors.red.shade900),
                            onPressed: viewModel.clearError,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Messages list, with the busy state for restoring a saved
              // conversation laid over it rather than in place of it. What is on
              // screen is about to be swapped for the restored conversation, and
              // swapping it for a spinner would read as the app going blank.
              Expanded(
                child: Stack(
                  children: [
                    ChatList(key: _chatKey, fontScale: appearance.fontScale),
                    if (viewModel.resumingSession) _resumeOverlay(context),
                  ],
                ),
              ),

              // Input area
              Container(
                padding: panelPadding,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // Model selector
                    const ModelSelector(),
                    const SizedBox(height: 12),

                    // What is about to be sent, shown before it is sent.
                    if (viewModel.attachments.isNotEmpty) ...[
                      AttachmentTray(
                        images: viewModel.attachments,
                        onRemove: viewModel.removeAttachmentAt,
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Input field
                    Row(
                      children: [
                        // Attaching sits next to sending rather than in a menu:
                        // the image is chosen because of what is being asked, and
                        // the two decisions happen in the same breath. It stays
                        // visible on a model that cannot see images, greyed out,
                        // so the reason is at least findable.
                        if (viewModel.deviceImagePickerAvailable)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Tooltip(
                              message: viewModel.attachmentUnavailableReason ??
                                  'Attach an image from this device',
                              child: FloatingActionButton(
                                mini: true,
                                heroTag: 'attach-image',
                                backgroundColor:
                                    viewModel.canAttachImages
                                        ? null
                                        : Colors.grey.shade300,
                                onPressed: viewModel.canAttachImages
                                    ? () => viewModel.attachImagesFromDevice()
                                    : null,
                                child:
                                    const Icon(Icons.add_photo_alternate_outlined),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Focus(
                            onKeyEvent: (node, event) {
                              // Enter submits; Ctrl+Enter inserts a newline.
                              if (event is KeyDownEvent &&
                                  (event.logicalKey ==
                                          LogicalKeyboardKey.enter ||
                                      event.logicalKey ==
                                          LogicalKeyboardKey.numpadEnter)) {
                                // While a run is in flight Enter falls through
                                // too: submitting would be ignored anyway, and
                                // swallowing the key would leave no way to
                                // compose the next message while the agent works.
                                if (HardwareKeyboard
                                        .instance.isControlPressed ||
                                    context.read<PiViewModel>().isLoading) {
                                  return KeyEventResult.ignored;
                                }
                                _sendPrompt(context.read<PiViewModel>());
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              controller: _inputController,
                              focusNode: _inputFocus,
                              onChanged: viewModel.setUserInput,
                              maxLines: null,
                              decoration: InputDecoration(
                                hintText: 'Enter a prompt or command...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Side by side, stop first. Stacked, the pair grew
                        // downwards into the space a phone reserves for its own
                        // gestures, and stop appeared exactly when the run was
                        // already long enough to need scrolling. In a row, stop
                        // takes room from the field instead and both stay under
                        // the thumb that has to reach them.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (viewModel.isLoading)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FloatingActionButton(
                                  mini: true,
                                  backgroundColor: Colors.red,
                                  // Stopping a run is not a run finishing: the
                                  // person pressing stop is the one thing that
                                  // already knows it ended.
                                  onPressed: () {
                                    _awaitingRunEnd = false;
                                    viewModel.abortCurrentTask();
                                  },
                                  child: const Icon(Icons.stop),
                                ),
                              ),
                            FloatingActionButton(
                              mini: true,
                              onPressed: viewModel.isLoading
                                  ? null
                                  : () => _sendPrompt(viewModel),
                              child: const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
