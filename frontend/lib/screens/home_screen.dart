import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/appearance_controller.dart';
import '../providers/pi_view_model.dart';
import '../widgets/chat_list.dart';
import '../widgets/directory_browser.dart';
import '../widgets/file_browser.dart';
import '../widgets/model_selector.dart';

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
    _chatKey.currentState?.stickToBottom();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_scrollChatWithPageKeys);
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
                            final title =
                                session.name != null && session.name!.isNotEmpty
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
                              ),
                              subtitle: Text(
                                '${session.messageCount} messages  •  '
                                '${_formatAge(session.modified)}  •  ${session.cwd}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () async {
                                Navigator.of(sheetContext).pop();
                                await vm.resumeSession(session.path);
                              },
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

  void _showDirectoryBrowser(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.7,
        child: const DirectoryBrowser(),
      ),
    );
  }

  void _showFileBrowser(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.8,
        child: const FileBrowser(),
      ),
    );
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
        final directory =
            viewModel.workingDirectoryDisplay ?? viewModel.workingDirectory ?? '';
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
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: theme.colorScheme.onSurface)),
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
                            viewModel.isConnected ? 'Connected' : 'Disconnected',
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
                            style: theme.textTheme.bodySmall
                                ?.copyWith(
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
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Working directory'),
                  subtitle: Text(directoryLabel.isEmpty
                      ? 'Not known yet'
                      : directoryLabel),
                  onTap: () {
                    closeMenu();
                    _showDirectoryBrowser(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Resume a previous session'),
                  enabled: !viewModel.resumingSession,
                  onTap: viewModel.resumingSession
                      ? null
                      : () {
                          closeMenu();
                          _showSessionPicker(context);
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('Browse and view files'),
                  onTap: () {
                    closeMenu();
                    _showFileBrowser(context);
                  },
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Appearance',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
                ListTile(
                  // The icon shows what is on the screen, because that is the
                  // only thing this control can truthfully act on: it moves away
                  // from whatever is currently being rendered.
                  leading: Icon(showingDark ? Icons.light_mode : Icons.dark_mode),
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
                            ? () =>
                                appearance.changeFont(larger: false)
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy, size: 24),
            const SizedBox(width: 8),
            const Text('Pi Agent'),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
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
          final panelPadding = EdgeInsets.only(
            left: math.max(16.0, insets.left),
            right: math.max(16.0, insets.right),
            top: 16,
            bottom: math.max(10.0, insets.bottom - 12),
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
                Container(
                  color: Colors.red.shade100,
                  padding: const EdgeInsets.all(12),
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

                    // Input field
                    Row(
                      children: [
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
                                  onPressed: viewModel.abortCurrentTask,
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
