import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../models/pi_models.dart';
import '../utils/clipboard.dart';
import '../utils/code_highlight.dart';
import '../utils/format.dart';
import '../utils/responsive.dart';
import '../utils/toast.dart';

class ChatBubble extends StatelessWidget {
  final PiMessage message;

  /// Live busy indicator for a reply that is still streaming. Only
  /// [ChatList] decides which bubble gets one, so a finished bubble never
  /// subscribes to the stream at all.
  final Widget? status;

  /// Whether this bubble takes the whole width of the chat instead of the usual
  /// column. Held by [ChatList], not by the bubble: bubbles are rebuilt from a
  /// cached body on every scroll and carry no key of their own, so state kept
  /// here would follow a position in the list rather than the message.
  final bool expanded;

  /// Double-click / double-tap the bubble. Null leaves it at its normal width.
  final VoidCallback? onToggleExpanded;

  /// Multiplier for every size in this bubble, from the app bar's text-size
  /// buttons. 1.0 is the size the bubbles were laid out for.
  ///
  /// Passed in rather than read from a provider here because the rendered body is
  /// cached: whatever the rendering depends on has to be part of the cache key, a
  /// size a bubble reads for itself would not be.
  final double fontScale;

  const ChatBubble({
    super.key,
    required this.message,
    this.status,
    this.expanded = false,
    this.onToggleExpanded,
    this.fontScale = 1.0,
  });

  /// One size in this bubble, scaled.
  ///
  /// The sizes stay written as the values the chat was designed at, so the
  /// design is still readable in the code and only one thing multiplies them.
  double _font(double base) => base * fontScale;

  @override
  Widget build(BuildContext context) {
    final isAssistant = message.role == 'assistant';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // An assistant reply that has started but has no text yet is Pi thinking.
    // Keeping it renders the bubble header plus its streaming spinner, which is
    // the typing indicator; empty finished messages stay hidden - unless the
    // provider reported why it failed, which is the whole content of that reply.
    if (message.content.isEmpty &&
        message.toolCalls.isEmpty &&
        message.errorMessage == null &&
        !message.streaming) {
      return const SizedBox.shrink();
    }

    // Bubble colours and text colours are chosen together so text always has
    // strong contrast, in both light and dark themes.
    final bubbleColor = isAssistant
        ? (isDark ? const Color(0xFF2A2D34) : Colors.grey.shade200)
        : (isDark ? const Color(0xFF1E3A5F) : Colors.blue.shade100);
    final mutedColor = isDark ? Colors.white70 : const Color(0x99000000);

    // Colour coding by output kind: assistant replies are teal-accented, your
    // own messages blue. A tool call is part of Pi's turn, so it stays in the
    // teal it is written in and is set apart by shape - a bordered, raised card
    // - rather than by a second hue. The amber card was the only warm colour in
    // the app, which is what made a command look like it came from somewhere
    // else. Results keep green: it is the one signal that says "this is output",
    // and a cool green sits with teal instead of fighting it.
    // All accent colours are tuned per theme so contrast is preserved.
    final accentColor = isAssistant
        ? (isDark ? const Color(0xFF4DD0E1) : const Color(0xFF00697A))
        : (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0B4D8C));
    // Tool calls only ever appear in an assistant reply, so the tool label uses
    // that reply's own accent - the same teal that says "Pi" in the header.
    final toolColor = accentColor;
    final toolResultColor =
        isDark ? const Color(0xFF7FCBA5) : const Color(0xFF2E6B4F);
    // A card raised off the bubble it sits on, tinted the same way as the
    // accent rather than tinted warm. Lighter than the bubble in both themes,
    // which is how the card already read before.
    final toolCardColor =
        isDark ? const Color(0xFF333A41) : const Color(0xFFF2F7F8);

    // Body text is tinted to match its source while staying high contrast
    // against the bubble it is rendered on.
    final bodyColor = isAssistant
        ? (isDark ? const Color(0xFFD3F1F6) : const Color(0xFF00495A))
        : (isDark ? const Color(0xFFC3DDF7) : const Color(0xFF0B3A66));

    // Rendering a bubble means parsing Markdown and highlighting every code
    // block, which is far too expensive to repeat while scrolling. The rendered
    // children are cached per message content, so re-entering the viewport
    // hands back the *same widget instances* and Flutter skips rebuilding those
    // subtrees entirely. Only a message that is still streaming changes.
    final cacheKey = _signatureOf(message, isDark, fontScale);
    final body = _BubbleBodyCache.lookup(cacheKey) ??
        _buildBody(context, message, bodyColor, toolColor, toolResultColor,
            toolCardColor, mutedColor, isDark);
    _BubbleBodyCache.store(cacheKey, body);

    // MediaQuery.sizeOf only depends on the window size, not on the soft
    // keyboard, so bubbles do not re-render every time the input field gains
    // focus on a phone.
    //
    // Use responsive sizing based on screen size for optimal readability:
    // - Phone: full width (already constrained by list padding)
    // - Tablet: narrower measure for better readability
    // - Desktop: even narrower for optimal line length
    //
    // Widening changes the limit, not the content: the Markdown body comes back
    // out of the cache as the same widget instances and re-lays out in the
    // wider box.
    final screenWidth = MediaQuery.sizeOf(context).width;
    // On a phone there is nothing wider to go to: the reply already takes the
    // column, so the double-tap would be a gesture that does nothing.
    final phone = ResponsiveSizes.isPhone(screenWidth);
    final maxWidth =
        ResponsiveSizes.getChatMaxWidth(screenWidth, expanded: expanded);

    // A bubble with nothing to say has nothing to copy: no button then.
    final copyText = message.copyableText;
    final canCopy = copyText.isNotEmpty;

    return Align(
      alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
      // Inside the alignment, so the gesture belongs to the bubble and not to
      // the empty stretch of row beside a short one.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: phone ? null : onToggleExpanded,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isAssistant ? Icons.smart_toy : Icons.person,
                    size: 16,
                    color: accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isAssistant ? 'Pi' : 'You',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: accentColor, fontWeight: FontWeight.bold),
                  ),
                  // Finished assistant replies carry the usage Pi reported for
                  // them, so each reply shows what it cost.
                  if (isAssistant &&
                      message.usage != null &&
                      !message.usage!.isEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${formatTokens(message.usage!.produced)} tok'
                      '${message.usage!.reasoning > 0 ? ' (thinking)' : ''}',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: mutedColor),
                    ),
                  ],
                  // Copy button in the top-right corner of the bubble. The header
                  // row already spans the whole bubble, so a Spacer puts it in the
                  // corner without changing any widths, and being in the row's own
                  // band it can never cover the reply.
                  if (canCopy) ...[
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.content_copy, size: 15),
                      color: mutedColor,
                      tooltip: 'Copy',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(26, 26),
                        padding: const EdgeInsets.all(4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _copyMessage(context, copyText),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              ...body,
              // The one busy indicator: passed in by ChatList for the bubble that
              // is actually streaming (or for the "thinking" placeholder), so
              // there is never a second spinner anywhere else.
              if (status != null) status!,
            ],
          ),
        ),
      ),
    );
  }

  /// Copies the whole reply - Markdown source, code fences included, which is
  /// what you want when you copy from a chat - and says whether it worked.
  Future<void> _copyMessage(BuildContext context, String text) async {
    final outcome = await copyToClipboard(text);
    if (!context.mounted) return;
    showToast(
      context,
      outcome == CopyOutcome.copied
          ? 'Copied to clipboard'
          : 'Copy failed - this browser blocked it',
      isError: outcome != CopyOutcome.copied,
    );
  }

  List<Widget> _buildBody(
      BuildContext context,
      PiMessage message,
      Color bodyColor,
      Color toolColor,
      Color toolResultColor,
      Color toolCardColor,
      Color mutedColor,
      bool isDark) {
    return [
      if (message.errorMessage != null)
        _buildModelError(context, message, isDark),
      if (message.content.isNotEmpty)
        _buildContent(context, message.content, bodyColor, isDark),
      for (final tool in message.toolCalls)
        _buildTool(context, tool, toolColor, toolResultColor, toolCardColor,
            mutedColor, isDark),
    ];
  }

  /// A response the provider refused. Pi reports why in `errorMessage`, and that
  /// text is the only thing the run produced - hiding it is what makes a model
  /// the account cannot use look like a model that is simply not answering.
  Widget _buildModelError(
      BuildContext context, PiMessage message, bool isDark) {
    final color = isDark ? const Color(0xFFFF8A80) : const Color(0xFF7F0000);
    final detail = message.errorMessage!.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message.stopReason == 'error' || message.stopReason == null
                  ? detail
                  : '$detail (${message.stopReason})',
              style: TextStyle(
                color: color,
                fontSize: _font(13),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Hash of everything the cached rendering depends on. Content length is
  /// folded in alongside the hash so two different messages cannot silently
  /// share an entry.
  ///
  /// The text size is part of it for the same reason the theme is: changing the
  /// size changes what the rendered children say, so a cache entry keyed without
  /// it would hand back the old sizes for content that has not changed - which is
  /// every message in the chat at once.
  static int _signatureOf(PiMessage message, bool isDark, double fontScale) {
    return Object.hash(
      message.role,
      isDark,
      fontScale,
      message.content.length,
      Object.hashAll(message.content.codeUnits),
      message.errorMessage,
      message.stopReason,
      message.toolCalls.length,
      Object.hashAll([
        for (final tool in message.toolCalls)
          Object.hash(
            tool.id,
            tool.name,
            tool.result?.length ?? -1,
            Object.hashAll((tool.result ?? '').codeUnits),
            Object.hashAll([
              for (final entry in tool.arguments.entries)
                Object.hash(entry.key, '${entry.value}'),
            ]),
          ),
      ]),
    );
  }

  Widget _buildContent(
      BuildContext context, String text, Color textColor, bool isDark) {
    try {
      // Check if it looks like markdown
      if (text.contains('```') || text.contains('#') || text.contains('**')) {
        return MarkdownBody(
          data: text,
          selectable: true,
          // Fenced code blocks get full syntax highlighting.
          builders: {
            'pre': _HighlightCodeBuilder(isDark: isDark, fontSize: _font(13)),
          },
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: TextStyle(fontSize: _font(14), color: textColor, height: 1.4),
            tableBody: TextStyle(fontSize: _font(13), color: textColor),
            code: TextStyle(
              fontSize: _font(13),
              fontFamily: 'JetBrainsMono',
              color: textColor,
              backgroundColor: isDark
                  ? Colors.white.withAlpha(30)
                  : Colors.black.withAlpha(20),
            ),
            h1: TextStyle(
                fontSize: _font(20),
                fontWeight: FontWeight.bold,
                color: textColor),
            h2: TextStyle(
                fontSize: _font(18),
                fontWeight: FontWeight.bold,
                color: textColor),
            h3: TextStyle(
                fontSize: _font(16),
                fontWeight: FontWeight.bold,
                color: textColor),
            strong: TextStyle(
                fontSize: _font(14),
                fontWeight: FontWeight.bold,
                color: textColor),
            blockquote: TextStyle(fontSize: _font(14), color: textColor),
          ),
        );
      }
    } catch (e) {
      // Fallback to plain text
    }

    return SelectableText(
      text,
      style: TextStyle(fontSize: _font(14), color: textColor, height: 1.4),
    );
  }

  Widget _buildTool(
      BuildContext context,
      PiTool tool,
      Color toolColor,
      Color toolResultColor,
      Color toolCardColor,
      Color mutedColor,
      bool isDark) {
    final args =
        tool.arguments.entries.map((e) => '${e.key}: ${e.value}').join(', ');

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: toolCardColor,
        border: Border.all(color: toolColor.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.build, size: 14, color: toolColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tool.name,
                  style: TextStyle(
                    fontSize: _font(12),
                    fontWeight: FontWeight.bold,
                    color: toolColor,
                  ),
                ),
              ),
            ],
          ),
          if (args.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                args,
                style: TextStyle(fontSize: _font(12), color: mutedColor),
              ),
            ),
          if (tool.result != null && tool.result!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildToolResult(tool.result!, toolResultColor, isDark),
            ),
        ],
      ),
    );
  }

  /// Tool results are usually code (JSON, source, command output). Highlight
  /// them when they look like code; otherwise keep the plain green monospace
  /// rendering so prose status messages stay readable.
  Widget _buildToolResult(String result, Color fallbackColor, bool isDark) {
    final source =
        result.length > 800 ? '${result.substring(0, 800)}…' : result;

    if (!_looksLikeCode(source)) {
      return Text(
        source,
        style: TextStyle(
            fontSize: _font(11),
            fontFamily: 'JetBrainsMono',
            color: fallbackColor),
      );
    }

    return HighlightedCode(
      source,
      isDark: isDark,
      // No background and no text colour: a command's output is code like any
      // other block in the reply, so it gets the same theme the reply uses.
      // Forcing the card's warm colour over it is what made tool output look
      // like it belonged to a different app.
      textStyle: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: _font(11),
      ),
    );
  }

  static bool _looksLikeCode(String source) {
    if (source.contains('\n')) return true;
    return RegExp(r'[{}<>;]|\[\w|\w\(').hasMatch(source);
  }
}

/// Cache of rendered bubble bodies, keyed by a signature of the message content,
/// theme and text size. Bounded so a long chat cannot grow memory without limit.
class _BubbleBodyCache {
  static final LinkedHashMap<int, List<Widget>> _entries =
      LinkedHashMap<int, List<Widget>>();
  static const int _maxEntries = 120;

  static List<Widget>? lookup(int key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value; // keep as most recently used
    return value;
  }

  static void store(int key, List<Widget> value) {
    if (_entries[key] == value) return;
    _entries[key] = value;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}

/// Renders fenced code blocks with syntax highlighting (colour formatting),
/// using the fence's language info string when present.
class _HighlightCodeBuilder extends MarkdownElementBuilder {
  _HighlightCodeBuilder({required this.isDark, required this.fontSize});

  final bool isDark;
  final double fontSize;

  String? _language;

  @override
  bool isBlockElement() => true;

  @override
  void visitElementBefore(md.Element element) {
    // The markdown parser puts the fence language on the inner <code>
    // element as class="language-<lang>".
    _language = null;
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final cls = child.attributes['class'] ?? '';
        final match = RegExp(r'language-([\w#+-]+)').firstMatch(cls);
        if (match != null) {
          _language = match.group(1);
        }
      }
    }
  }

  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) {
    // Fences without an info string (```) get auto-detected by the
    // highlighter; unknown content falls back to plain monospace text.
    return HighlightedCode(
      text.text,
      language: _language,
      isDark: isDark,
      textStyle: TextStyle(fontSize: fontSize),
    );
  }
}
