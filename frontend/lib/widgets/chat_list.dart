import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:provider/provider.dart';
import '../models/pi_models.dart';
import '../providers/pi_view_model.dart';
import 'chat_bubble.dart';
import 'turn_status.dart';

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
  bool _lastThinking = false;
  int _stickAttempts = 0;

  /// Which messages the user has widened to the full column.
  ///
  /// This lives with the list, not with the bubble. Bubbles are rebuilt from a
  /// cached body on every scroll and are keyed by nothing, so state held in one
  /// would follow its position in the list - widen a reply, resume a session,
  /// and the width would land on whichever message happened to share the slot.
  final Set<String> _expandedIds = {};

  void _toggleExpanded(String key) {
    setState(() {
      if (!_expandedIds.remove(key)) _expandedIds.add(key);
    });
  }

  /// What a widened state is keyed on for a given message.
  ///
  /// Pi gives every message an id. A history entry that arrives without one
  /// falls back to its position: the list only ever grows at the end, so a
  /// position is as stable as that message can be. Keying on the empty id
  /// instead would widen every id-less message together, and refusing to key at
  /// all would make double-clicking them do nothing.
  String _widenedKey(int index, PiMessage message) =>
      message.id.isNotEmpty ? message.id : '#$index';

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

  /// Scroll one viewport up or down: the PageUp / PageDown keys on a desktop
  /// keyboard.
  ///
  /// Returns whether anything moved. At the very top or bottom there is nothing
  /// to do, and the caller should not claim the key for nothing.
  ///
  /// A page is 90% of the viewport, not 100%: keeping a sliver of the previous
  /// screen is what makes paging readable instead of jumping somewhere
  /// unrecognisable. Landing back at the bottom resumes following the live chat.
  bool scrollByPage({required bool forward}) {
    if (!mounted || !_scrollController.hasClients) return false;

    final position = _scrollController.position;
    final page = position.viewportDimension * 0.9;
    final target = (position.pixels + (forward ? page : -page))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return false;

    // Jump, not animate: paging is a repeated key, and an animation would be
    // interrupted by the next press and look like sliding mush.
    position.jumpTo(target);

    final following =
        position.maxScrollExtent - position.pixels <= _stickTolerance;
    if (following != _followLatest) setState(() => _followLatest = following);
    if (following) _stickAttempts = 0;
    return true;
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
    return Selector<PiViewModel, (int, bool)>(
      selector: (_, viewModel) =>
          (viewModel.messagesVersion, viewModel.awaitingModel),
      builder: (context, state, _) {
        final (version, thinking) = state;
        // Runs only when the message list changes or the thinking indicator
        // flips; the bubbles themselves are cached by ChatBubble, so unchanged
        // ones are not re-rendered.
        if (version != _lastVersion || thinking != _lastThinking) {
          _lastVersion = version;
          _lastThinking = thinking;
          _scheduleStick();
        }

        final messages = context.read<PiViewModel>().messages;

        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              scrollCacheExtent: _cacheExtent,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length + (thinking ? 1 : 0),
              itemBuilder: (context, index) {
                final bubble = index == messages.length
                    // Not a stored message: exactly the bubble an empty
                    // streaming reply renders, so the indicator matches Pi's
                    // own replies instead of inventing its own design.
                    ? ChatBubble(
                        message: PiMessage(
                          id: 'thinking',
                          role: 'assistant',
                          content: '',
                          timestamp: DateTime.now(),
                          streaming: true,
                        ),
                        expanded: _expandedIds.contains('thinking'),
                        onToggleExpanded: () => _toggleExpanded('thinking'),
                        status: const TurnStatusRow(),
                      )
                    : ChatBubble(
                        message: messages[index],
                        // Pi gives every message an id. A history entry that
                        // arrives without one falls back to its position: the
                        // list only ever grows at the end, so a position is as
                        // stable as that message can be. Keying on nothing at
                        // all would make two such messages widen together, and
                        // keying on nothing for real would make double-clicking
                        // them do nothing at all.
                        expanded: _expandedIds
                            .contains(_widenedKey(index, messages[index])),
                        onToggleExpanded: () => _toggleExpanded(
                            _widenedKey(index, messages[index])),
                        // The reply Pi is still writing carries the live status;
                        // finished ones carry nothing, and stay cached.
                        status: messages[index].streaming
                            ? const TurnStatusRow()
                            : null,
                      );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: bubble,
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
