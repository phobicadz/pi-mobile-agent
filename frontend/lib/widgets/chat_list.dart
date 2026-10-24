import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:provider/provider.dart';
import '../providers/pi_view_model.dart';
import 'chat_bubble.dart';

/// The chat scroll view, kept separate from the rest of the screen.
///
/// It rebuilds only when the message list actually changes
/// ([PiViewModel.messagesVersion]) instead of on every view-model notification,
/// and it follows the conversation while Pi is streaming without fighting the
/// user's own scroll gestures.
class ChatList extends StatefulWidget {
  const ChatList({super.key});

  @override
  State<ChatList> createState() => ChatListState();
}

class ChatListState extends State<ChatList> {
  /// Distance from the bottom that still counts as "following the chat".
  static const double _stickTolerance = 120;

  /// Build bubbles before they scroll into view, so scrolling shows finished
  /// content instead of waiting on work done mid-scroll.
  static const ScrollCacheExtent _cacheExtent = ScrollCacheExtent.viewport(1.5);

  final ScrollController _scrollController = ScrollController();
  bool _followLatest = true;
  bool _scrollScheduled = false;
  int _lastVersion = -1;
  int _stickAttempts = 0;

  /// Bubbles have no fixed height, so maxScrollExtent is only an estimate for
  /// the part of the list that has not been laid out yet. A single jump can
  /// land short; following it for a few frames lands on the real bottom.
  static const int _maxFollowUpFrames = 8;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final following =
        position.maxScrollExtent - position.pixels <= _stickTolerance;
    if (following == _followLatest || !mounted) return;

    // Scroll notifications can arrive while the framework is still running
    // build/layout callbacks; deferring keeps setState() out of that phase.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _followLatest = following);
      });
    } else {
      setState(() => _followLatest = following);
    }
  }

  /// Move to the newest message.
  ///
  /// Streaming appends content on every update, so an animated scroll would be
  /// restarted over and over — that stutter is most of what "janky chat" feels
  /// like. A jump tracks the text exactly, and it repeats for a few frames
  /// because the bottom of a variable-height list is only known once the
  /// bubbles below it have been laid out.
  void stickToBottom() {
    if (!mounted) return;
    if (!_followLatest) setState(() => _followLatest = true);
    _stickAttempts = 0;
    _stickNow();
  }

  void _stickNow() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Already at the bottom: nothing to follow, and the next message re-triggers
    // this through the version bump anyway.
    if (position.pixels >= position.maxScrollExtent) return;
    position.jumpTo(position.maxScrollExtent);
    if (!_followLatest || _stickAttempts >= _maxFollowUpFrames) return;
    _stickAttempts++;
    WidgetsBinding.instance.addPostFrameCallback((_) => _stickNow());
  }

  void _scheduleStick() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (mounted && _followLatest) stickToBottom();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Selector<PiViewModel, int>(
      selector: (_, viewModel) => viewModel.messagesVersion,
      builder: (context, version, _) {
        // Runs only when the message list changes; the bubbles themselves are
        // cached by ChatBubble, so unchanged ones are not re-rendered.
        if (version != _lastVersion) {
          _lastVersion = version;
          _scheduleStick();
        }

        final messages = context.read<PiViewModel>().messages;

        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              scrollCacheExtent: _cacheExtent,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ChatBubble(message: message),
                );
              },
            ),
            if (!_followLatest)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  mini: true,
                  tooltip: 'Jump to the newest message',
                  onPressed: stickToBottom,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              ),
          ],
        );
      },
    );
  }
}
