import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/pi_view_model.dart';
import '../widgets/chat_list.dart';
import '../widgets/directory_browser.dart';
import '../widgets/model_selector.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _chatKey = GlobalKey<ChatListState>();
  final _inputController = TextEditingController();

  /// PageUp / PageDown are desktop keys - a physical keyboard, or a desktop
  /// browser (on the web `defaultTargetPlatform` reports the browser's OS).
  static bool get _pageKeysExpected => const {
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    if (_pageKeysExpected) {
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
    _chatKey.currentState?.stickToBottom();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_scrollChatWithPageKeys);
    _inputController.dispose();
    super.dispose();
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
                            final title = session.name != null &&
                                    session.name!.isNotEmpty
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

  String _shortenPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return path;
    if (segments.length <= 2) return path;
    return '.../${segments.sublist(segments.length - 2).join('/')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Selector<PiViewModel, bool>(
          // Disabled while a run is in flight: starting over mid-run would
          // throw away a reply that is still being written.
          selector: (_, viewModel) => viewModel.isLoading,
          builder: (context, busy, _) {
            return IconButton(
              icon: const Icon(Icons.add),
              tooltip: busy
                  ? 'Finish or stop the current run first'
                  : 'New session in this directory',
              onPressed: busy ? null : () => _startNewSession(context),
            );
          },
        ),
        title: const Text('Pi Agent'),
        centerTitle: true,
        elevation: 0,
        actions: [
          Selector<PiViewModel, String?>(
            // Only the directory text needs to rebuild when the working
            // directory changes, not the whole app bar on every update.
            selector: (_, viewModel) =>
                viewModel.workingDirectoryDisplay ?? viewModel.workingDirectory,
            builder: (context, cwd, _) {
              return Tooltip(
                message: 'Browse and set the working directory',
                child: TextButton.icon(
                  icon: const Icon(Icons.folder_outlined, size: 18),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      cwd == null || cwd.isEmpty
                          ? 'Directory'
                          : _shortenPath(cwd),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onPressed: () => _showDirectoryBrowser(context),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Resume a previous session',
            onPressed: () => _showSessionPicker(context),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Center(
              child: Selector<PiViewModel, bool>(
                selector: (_, viewModel) => viewModel.isConnected,
                builder: (context, isConnected, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isConnected ? 'Connected' : 'Disconnected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
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

              // Messages list
              Expanded(child: ChatList(key: _chatKey)),

              // Input area
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                ),
                child: SafeArea(
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
                                // Enter submits, Ctrl+Enter inserts a newline.
                                if (event is KeyDownEvent &&
                                    (event.logicalKey ==
                                            LogicalKeyboardKey.enter ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.numpadEnter)) {
                                  if (HardwareKeyboard.instance
                                      .isControlPressed) {
                                    return KeyEventResult.ignored;
                                  }
                                  _sendPrompt(
                                      context.read<PiViewModel>());
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: TextField(
                                controller: _inputController,
                                onChanged: viewModel.setUserInput,
                                enabled: !viewModel.isLoading,
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
                          Column(
                            children: [
                              FloatingActionButton(
                                mini: true,
                                onPressed: viewModel.isLoading
                                    ? null
                                    : () => _sendPrompt(viewModel),
                                child: const Icon(Icons.send),
                              ),
                              if (viewModel.isLoading)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: FloatingActionButton(
                                    mini: true,
                                    backgroundColor: Colors.red,
                                    onPressed: viewModel.abortCurrentTask,
                                    child: const Icon(Icons.stop),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
