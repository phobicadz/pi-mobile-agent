import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:markdown/markdown.dart' as md;
import '../models/pi_models.dart';

class ChatBubble extends StatelessWidget {
  final PiMessage message;

  const ChatBubble({
    Key? key,
    required this.message,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isAssistant = message.role == 'assistant';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Bubble colors and text colors are chosen together so text always has
    // strong contrast, in both light and dark themes.
    final bubbleColor = isAssistant
        ? (isDark ? const Color(0xFF2A2D34) : Colors.grey.shade200)
        : (isDark ? const Color(0xFF1E3A5F) : Colors.blue.shade100);
    final mutedColor = isDark ? Colors.white70 : const Color(0x99000000);

    // Colour coding by output kind: assistant replies are teal-accented,
    // your own messages blue, and tool calls amber with green results.
    // All accent colours are tuned per theme so contrast is preserved.
    final accentColor = isAssistant
        ? (isDark ? const Color(0xFF4DD0E1) : const Color(0xFF00697A))
        : (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0B4D8C));
    final toolColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFF8A5A00);
    final toolResultColor =
        isDark ? const Color(0xFF9CCC65) : const Color(0xFF2E6B12);
    final toolCardColor = isDark
        ? const Color(0xFF3A3427)
        : const Color(0xFFFFF6E0);

    // Body text is tinted to match its source while staying high contrast
    // against the bubble it is rendered on.
    final bodyColor = isAssistant
        ? (isDark ? const Color(0xFFD3F1F6) : const Color(0xFF00495A))
        : (isDark ? const Color(0xFFC3DDF7) : const Color(0xFF0B3A66));

    if (message.content.isEmpty && message.toolCalls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
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
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: accentColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (message.content.isNotEmpty)
              _buildContent(context, message.content, bodyColor, isDark),

            for (final tool in message.toolCalls)
              _buildTool(context, tool, toolColor, toolResultColor,
                  toolCardColor, mutedColor, isDark),

            if (message.streaming)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: mutedColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, String text, Color textColor,
      bool isDark) {
    try {
      // Check if it looks like markdown
      if (text.contains('```') || text.contains('#') || text.contains('**')) {
        return MarkdownBody(
          data: text,
          selectable: true,
          // Fenced code blocks get full syntax highlighting.
          builders: {'pre': _HighlightCodeBuilder(isDark: isDark)},
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: TextStyle(fontSize: 14, color: textColor, height: 1.4),
            tableBody: TextStyle(fontSize: 13, color: textColor),
            code: TextStyle(
              fontSize: 13,
              fontFamily: 'JetBrainsMono',
              color: textColor,
              backgroundColor: isDark
                  ? Colors.white.withAlpha(30)
                  : Colors.black.withAlpha(20),
            ),
            h1: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textColor),
            h2: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor),
            h3: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor),
            strong: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
            blockquote: TextStyle(fontSize: 14, color: textColor),
          ),
        );
      }
    } catch (e) {
      // Fallback to plain text
    }

    return SelectableText(
      text,
      style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
    );
  }

  Widget _buildTool(BuildContext context, PiTool tool, Color toolColor,
      Color toolResultColor, Color toolCardColor, Color mutedColor,
      bool isDark) {
    final args = tool.arguments.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');

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
                    fontSize: 12,
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
                style: TextStyle(fontSize: 12, color: mutedColor),
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
  /// them when a language can be detected; otherwise keep the plain green
  /// monospace rendering so prose status messages stay readable.
  Widget _buildToolResult(String result, Color fallbackColor, bool isDark) {
    final source =
        result.length > 800 ? '${result.substring(0, 800)}…' : result;

    final detected = _looksLikeCode(source)
        ? highlight.parse(source, autoDetection: true).language
        : null;

    if (detected == null || detected == 'plaintext') {
      return Text(
        source,
        style: TextStyle(
            fontSize: 11, fontFamily: 'JetBrainsMono', color: fallbackColor),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2D34) : const Color(0xFFFFFDF5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: HighlightView(
        source,
        language: detected,
        theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
        padding: const EdgeInsets.all(6),
        textStyle: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
      ),
    );
  }

  static bool _looksLikeCode(String source) {
    if (source.contains('\n')) return true;
    return RegExp(r'[{}<>;]|\[\w|\w\(').hasMatch(source);
  }
}

/// Renders fenced code blocks with syntax highlighting (colour formatting),
/// using the fence's language info string when present.
class _HighlightCodeBuilder extends MarkdownElementBuilder {
  _HighlightCodeBuilder({required this.isDark});

  final bool isDark;

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

  /// `highlight.parse` throws when `language` is null, so fences without an
  /// info string (bare ```) must resolve to a concrete language. Auto-detection
  /// keeps such blocks highlighted; unknown content falls back to plaintext.
  String _resolveLanguage(String source) {
    if (_language != null) return _language!;
    return highlight.parse(source, autoDetection: true).language ?? 'plaintext';
  }

  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) {
    return HighlightView(
      text.text,
      language: _resolveLanguage(text.text),
      theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
      padding: const EdgeInsets.all(8),
      textStyle: const TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 13,
      ),
    );
  }
}
