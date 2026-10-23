import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pi_view_model.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/directory_browser.dart';
import '../widgets/model_selector.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Scroll to bottom when new events arrive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
        title: const Text('Pi Agent'),
        centerTitle: true,
        elevation: 0,
        actions: [
          Consumer<PiViewModel>(
            builder: (context, viewModel, _) {
              final cwd =
                  viewModel.workingDirectoryDisplay ?? viewModel.workingDirectory;
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
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Consumer<PiViewModel>(
                builder: (context, viewModel, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: viewModel.isConnected ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      viewModel.isConnected ? 'Connected' : 'Disconnected',
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
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: viewModel.messages.length,
                  itemBuilder: (context, index) {
                    final message = viewModel.messages[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ChatBubble(message: message),
                    );
                  },
                ),
              ),

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
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              FloatingActionButton(
                                mini: true,
                                onPressed: viewModel.isLoading
                                    ? null
                                    : () {
                                        viewModel.submitPrompt();
                                        _inputController.clear();
                                        _scrollToBottom();
                                      },
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
