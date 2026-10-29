import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/pi_models.dart';
import '../providers/pi_view_model.dart';
import '../utils/code_highlight.dart';

/// A modal that displays the contents of a file: line numbers down the left,
/// the file's own colours on the right.
class FileViewer extends StatefulWidget {
  final String filePath;
  final String? fileName;

  const FileViewer({
    super.key,
    required this.filePath,
    this.fileName,
  });

  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  FileContent? _content;
  bool _loading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  /// Highlighting and line splitting are synchronous work on the UI thread. A
  /// chat only parses a fenced block; a whole file is parsed in one go, so a
  /// large source file would stall the dialog. Past this size the file is shown
  /// plain, with the reason said out loud.
  static const int _maxHighlightChars = 120 * 1024;

  /// The language the file was coloured with, and how it was chosen: 'named'
  /// from the extension, 'guessed' by the highlighter, or none at all. The
  /// header says which, so a wrong colouring is not a mystery.
  String? _languageLabel;

  /// The foreground and background the palette expects its token colours to be
  /// seen on. The file is painted on these, not on the dialog's own colours.
  ({Color foreground, Color background})? _palette;

  /// The brightness the spans were prepared for, so switching the app between
  /// light and dark re-colours a file that is already open.
  Brightness? _preparedBrightness;

  /// One span list per line, produced once when the file loads.
  List<List<TextSpan>>? _lines;

  static const _monoFamily = 'JetBrainsMono';
  static const _fontSize = 12.0;
  static const _lineHeight = 1.5;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_preparedBrightness != null &&
        _preparedBrightness != brightness &&
        _content != null) {
      setState(() => _prepare(_content!));
    }
    _preparedBrightness = brightness;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final vm = context.read<PiViewModel>();
      final content = await vm.readFile(widget.filePath);
      if (!mounted) return;

      // PiViewModel reports a failed command by returning null and keeping the
      // reason in `error`; the viewer has to carry that over or a failed read
      // shows as an empty panel with no explanation.
      setState(() {
        _loading = false;
        if (content != null) {
          _content = content;
          _prepare(content);
        } else {
          _error = vm.error ?? 'Could not read that file.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  TextStyle _baseStyle(Color foreground) => TextStyle(
        fontFamily: _monoFamily,
        fontSize: _fontSize,
        height: _lineHeight,
        color: foreground,
      );

  void _prepare(FileContent content) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = codePalette(isDark);
    final baseStyle = _baseStyle(palette.foreground);
    final mapped = languageForPath(widget.filePath);
    final prose = isProsePath(widget.filePath);
    final tooLarge = content.content.length > _maxHighlightChars;

    _palette = palette;
    _preparedBrightness = Theme.of(context).brightness;

    // Text files whose extension the mapping does not know are still offered to
    // the highlighter: a `.cshtml`, a `.mjs`, or a file saved without an
    // extension is code, and guessing is better than showing it uncoloured.
    // Prose is excluded - colouring a README because a line looked like a
    // comment is worse than leaving it plain.
    final bool tryHighlight =
        content.isText && !tooLarge && !prose;

    String? language;
    List<TextSpan>? spans;
    if (tryHighlight) {
      language = mapped;
      spans = highlightedSpans(
        content.content,
        language: mapped,
        isDark: isDark,
      );
    }

    if (spans == null || spans.isEmpty) {
      _languageLabel = prose
          ? 'plain text'
          : (tooLarge ? 'not coloured (too large)' : null);
      _lines = plainLines(content.content, baseStyle);
      return;
    }

    _languageLabel = language != null
        ? languageDisplayName(language).toLowerCase()
        : 'guessed';
    _lines = splitSpansByLine(spans);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Width of the gutter: wide enough for the largest line number, measured in
  /// the same monospace font the code is drawn in.
  double _gutterWidth(int lineCount, Color colour) {
    final digits = lineCount.toString().length;
    final painter = TextPainter(
      text: TextSpan(
        text: '9' * digits,
        style: TextStyle(
          fontFamily: _monoFamily,
          fontSize: _fontSize - 1,
          color: colour,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + 16;
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    final lines = _lines;
    if (lines == null || lines.isEmpty) return const SizedBox.shrink();

    // The palette's own surface, because its token colours were chosen against
    // it. Painting them on the dialog's background instead is what made the
    // colouring look wrong, and look wrong differently in light and in dark.
    final palette = _palette ?? codePalette(theme.brightness == Brightness.dark);
    final baseStyle = _baseStyle(palette.foreground);
    final gutter = _gutterWidth(lines.length, palette.foreground);
    final numberStyle = TextStyle(
      fontFamily: _monoFamily,
      fontSize: _fontSize - 1,
      color: palette.foreground.withValues(alpha: 0.45),
    );
    // One row per line number, so a blank line still occupies a line: without
    // it the numbers drift out of step with the source they number.
    final rowHeight = _fontSize * _lineHeight;

    return ColoredBox(
      color: palette.background,
      child: SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: gutter,
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.right,
                        style: numberStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: rowHeight),
                        child: RichText(
                          text: TextSpan(
                            style: baseStyle,
                            children: lines[index],
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = _content;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Container(
            // The header belongs to the dialog, so it is painted with the
            // dialog's own colours and reads in both appearances. A fixed
            // white-on-primary is only correct in one of them: in a dark
            // Material 3 scheme `primary` is a light blue, and white text on it
            // is the part of this screen that looked wrong.
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName ?? 'File Viewer',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: theme.colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (content != null)
                        Text(
                          [
                            _formatFileSize(content.size),
                            if (_lines != null) '${_lines!.length} lines',
                            if (_languageLabel != null) _languageLabel!,
                            if (!content.isText) 'binary',
                          ].join(' • '),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (content != null)
                  IconButton(
                    icon: Icon(Icons.copy, color: theme.colorScheme.onSurfaceVariant),
                    tooltip: 'Copy file',
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: content.content));
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('File copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                IconButton(
                  icon: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 48, color: theme.colorScheme.error),
                              const SizedBox(height: 16),
                              Text(
                                'Error loading file',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _error!,
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : content == null
                        ? const Center(child: Text('No content'))
                        : Scrollbar(
                            controller: _scrollController,
                            child: _buildBody(context, theme),
                          ),
          ),
        ],
      ),
    );
  }
}
