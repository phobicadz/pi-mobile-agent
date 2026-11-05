import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pi_models.dart';
import '../providers/appearance_controller.dart';
import '../providers/pi_view_model.dart';
import '../utils/clipboard.dart';
import '../utils/code_highlight.dart';
import '../utils/toast.dart';

/// A modal that displays the contents of a file: line numbers down the left,
/// the file's own colours on the right.
class FileViewer extends StatefulWidget {
  final String filePath;
  final String? fileName;

  /// Hands a `path:line` reference to whatever opened this viewer, for it to put
  /// into the prompt the user was already typing. Left null where there is no
  /// prompt to write into, and the viewer offers copying only.
  final void Function(String reference)? onUseInPrompt;

  const FileViewer({
    super.key,
    required this.filePath,
    this.fileName,
    this.onUseInPrompt,
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

  /// The lines the user has pointed at by tapping their numbers, and the line
  /// the current selection was anchored to. A reference to a file is a path and
  /// a line range, and the line is the part you can only point at on screen.
  int? _anchorLine;
  int? _selectedStart;
  int? _selectedEnd;

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
    final bool tryHighlight = content.isText && !tooLarge && !prose;

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
      _languageLabel =
          prose ? 'plain text' : (tooLarge ? 'not coloured (too large)' : null);
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
  /// the same monospace font the code is drawn in, at the size it is drawn in.
  double _gutterWidth(int lineCount, Color colour, double numberSize) {
    final digits = lineCount.toString().length;
    final painter = TextPainter(
      text: TextSpan(
        text: '9' * digits,
        style: TextStyle(
          fontFamily: _monoFamily,
          fontSize: numberSize,
          color: colour,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + 16;
  }

  /// Tapping a line number selects that line, tapping another extends the
  /// selection to a range, and tapping the same one again clears it.
  ///
  /// Lines are numbered as they are displayed - from 1 - because that is what a
  /// `path:line` reference means to every tool that reads one, editors included.
  void _tapLine(int line) {
    setState(() {
      if (_selectedStart == null) {
        _anchorLine = line;
        _selectedStart = line;
        _selectedEnd = line;
        return;
      }
      if (line == _selectedStart && line == _selectedEnd) {
        _anchorLine = null;
        _selectedStart = null;
        _selectedEnd = null;
        return;
      }
      final anchor = _anchorLine!;
      _selectedStart = math.min(anchor, line);
      _selectedEnd = math.max(anchor, line);
    });
  }

  bool get _hasSelection => _selectedStart != null;

  /// The reference itself: the path the file was opened by, and the lines.
  ///
  /// Absolute, on purpose. The agent runs in whatever directory the session was
  /// pointed at, and the file was browsed from wherever the user was standing;
  /// a path that only makes sense from one of those is a path the agent cannot
  /// open. The `:line` suffix is the form editors, `git diff` and every code
  /// tool already agree on.
  String _lineReference() {
    final start = _selectedStart!;
    final end = _selectedEnd!;
    return start == end
        ? '${widget.filePath}:$start'
        : '${widget.filePath}:$start-$end';
  }

  /// The same reference as the toast says it. A 380px toast cannot show an
  /// absolute path, and a message cut off mid-way reads as a broken one.
  String _shortLineReference() {
    final name = widget.filePath
        .replaceAll(RegExp(r'[\\/]+$'), '')
        .split(RegExp(r'[\\/]'))
        .last;
    final start = _selectedStart!;
    final end = _selectedEnd!;
    return start == end ? '$name:$start' : '$name:$start-$end';
  }

  String get _referenceLabel => _selectedStart == _selectedEnd
      ? 'Copy reference to line $_selectedStart'
      : 'Copy reference to lines $_selectedStart–$_selectedEnd';

  /// Re-styles the spans for the size the text is being shown at.
  ///
  /// The spans carry the colours the palette chose; the size is ours. This runs
  /// for the rows on screen only, which is why changing the size does not make
  /// the viewer re-parse the file.
  List<TextSpan> _sizedSpans(List<TextSpan> spans, TextStyle scaled) => [
        for (final span in spans)
          TextSpan(
            text: span.text,
            style: span.style == null
                ? scaled
                : span.style!.copyWith(
                    fontSize: scaled.fontSize, fontFamily: _monoFamily),
          ),
      ];

  Widget _buildBody(BuildContext context, ThemeData theme, double fontScale) {
    final lines = _lines;
    if (lines == null || lines.isEmpty) return const SizedBox.shrink();

    // The palette's own surface, because its token colours were chosen against
    // it. Painting them on the dialog's background instead is what made the
    // colouring look wrong, and look wrong differently in light and in dark.
    final palette =
        _palette ?? codePalette(theme.brightness == Brightness.dark);
    final codeSize = _fontSize * fontScale;
    final baseStyle =
        _baseStyle(palette.foreground).copyWith(fontSize: codeSize);
    final gutter = _gutterWidth(lines.length, palette.foreground, codeSize - 1);
    final numberStyle = TextStyle(
      fontFamily: _monoFamily,
      fontSize: codeSize - 1,
      color: palette.foreground.withValues(alpha: 0.45),
    );
    final selectedNumberStyle = numberStyle.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.bold,
    );
    // A selected line is painted as a band across the row, so the range being
    // referenced is visible in the file and not only in the button's label.
    final selectionBand = theme.colorScheme.primary
        .withValues(alpha: theme.brightness == Brightness.dark ? 0.18 : 0.10);
    // One row per line number, so a blank line still occupies a line: without
    // it the numbers drift out of step with the source they number.
    final rowHeight = codeSize * _lineHeight;

    return ColoredBox(
      color: palette.background,
      child: SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            final line = index + 1;
            final selected = _hasSelection &&
                line >= _selectedStart! &&
                line <= _selectedEnd!;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ColoredBox(
                color: selected ? selectionBand : Colors.transparent,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _tapLine(line),
                        child: Semantics(
                          button: true,
                          label: 'Reference line $line',
                          child: SizedBox(
                            width: gutter,
                            child: Text(
                              '$line',
                              textAlign: TextAlign.right,
                              style:
                                  selected ? selectedNumberStyle : numberStyle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: rowHeight),
                          child: RichText(
                            text: TextSpan(
                              style: baseStyle,
                              children: _sizedSpans(lines[index], baseStyle),
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Copy the file, and say whether it worked - in the same words and the same
  /// place the chat's copy buttons do.
  ///
  /// `Clipboard.setData` on its own is the one that does nothing here: this app
  /// runs on a plain `http://<lan-ip>:3000` origin, where the browser has no
  /// Clipboard API, and the engine turns that into an exception nobody reports.
  /// `copyToClipboard` is the path that survives it, and it answers with an
  /// outcome instead of an exception so the button can say which happened.
  Future<void> _copyFile(BuildContext insideDialog, String text) async {
    final outcome = await copyToClipboard(text);
    if (!mounted) return;
    showToast(
      insideDialog,
      outcome == CopyOutcome.copied
          ? 'Copied file'
          : 'Copy failed - this browser blocked it',
      isError: outcome != CopyOutcome.copied,
    );
  }

  /// Copy a `path:line` reference to the lines the user pointed at, so they can
  /// paste it into a prompt and the agent lands on those lines.
  ///
  /// The whole file is already copyable; what a viewer cannot otherwise give is
  /// the position you were looking at. A line number on a screen is not something
  /// an agent can be told, and retyping a path and a number is where a reference
  /// like this gets lost.
  Future<void> _copyLineReference(BuildContext insideDialog) async {
    final reference = _lineReference();
    final outcome = await copyToClipboard(reference);
    if (!mounted) return;
    showToast(
      insideDialog,
      outcome == CopyOutcome.copied
          ? 'Copied ${_shortLineReference()}'
          : 'Copy failed - this browser blocked it',
      isError: outcome != CopyOutcome.copied,
    );
  }

  /// Put the reference into the prompt the user was already typing.
  ///
  /// Copying it is a two-step route to the same place - clipboard, then paste -
  /// and on a phone the prompt field is not even on screen while this dialog is
  /// open. Inserting it here is one tap.
  ///
  /// This dialog closes itself first. `Navigator.pop` removes the topmost route,
  /// and the callback goes on to close the browser sheet underneath; the other
  /// order closes this dialog twice and leaves the sheet where it was.
  void _useInPrompt(BuildContext insideDialog) {
    final onUse = widget.onUseInPrompt;
    if (onUse == null) return;
    final reference = _lineReference();
    Navigator.of(insideDialog).pop();
    onUse(reference);
  }

  /// The viewer's controls, spelled out rather than left to icons.
  ///
  /// The text size lives here and not in the app's menu because it is a decision
  /// about this file, taken while looking at it - and the chat's size is a
  /// different size for different text, which is why the two are separate
  /// settings. See `AppearanceController`.
  Widget _buildToolbar(
      BuildContext context, ThemeData theme, AppearanceController appearance) {
    final scale = appearance.fileFontScale;
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.text_decrease,
              color: theme.colorScheme.onSurfaceVariant),
          tooltip: 'Smaller file text',
          onPressed: appearance.canDecreaseFileFont
              ? () => appearance.changeFileFont(larger: false)
              : null,
        ),
        Text(
          '${(scale * 100).round()}% text size',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.text_increase,
              color: theme.colorScheme.onSurfaceVariant),
          tooltip: 'Larger file text',
          onPressed: appearance.canIncreaseFileFont
              ? () => appearance.changeFileFont(larger: true)
              : null,
        ),
        const SizedBox(width: 10),
        if (_hasSelection) ...[
          // Both inside a Builder so their confirmations go to the messenger in
          // this dialog, for the same reason the copy button is.
          if (widget.onUseInPrompt != null)
            Builder(
              builder: (inside) => FilledButton.tonalIcon(
                onPressed: () => _useInPrompt(inside),
                icon: const Icon(Icons.add_to_queue, size: 18),
                label: Text(_selectedStart == _selectedEnd
                    ? 'Put line $_selectedStart in the prompt'
                    : 'Put lines $_selectedStart–$_selectedEnd in the prompt'),
              ),
            ),
          Builder(
            builder: (inside) => TextButton.icon(
              onPressed: () => _copyLineReference(inside),
              icon: const Icon(Icons.link, size: 18),
              label: Text(_referenceLabel),
            ),
          ),
        ] else
          // Said out loud because "tap a line number" is not an affordance a
          // number in the margin announces by itself.
          Text(
            'Tap a line number to reference it',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appearance = context.watch<AppearanceController>();
    final content = _content;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.all(8),
      // The confirmation belongs inside this dialog. A SnackBar normally goes to
      // the app's own Scaffold, which sits *behind* this dialog route - on a
      // phone, where the dialog reaches the bottom of the screen, that is a
      // confirmation nobody can see. This messenger and this scaffold are the
      // ones inside the dialog, so the toast lands on top of it.
      child: ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: Column(
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.fileName ?? 'File Viewer',
                                style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.onSurface),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (content != null)
                                Text(
                                  [
                                    _formatFileSize(content.size),
                                    if (_lines != null)
                                      '${_lines!.length} lines',
                                    if (_languageLabel != null) _languageLabel!,
                                    if (!content.isText) 'binary',
                                  ].join(' • '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        if (content != null)
                          // A Builder, so the copy is reported through the messenger
                          // inside this dialog. An inherited lookup starts above the
                          // widget that does it: asking from the viewer's own context
                          // reaches the app's Scaffold, which is behind the dialog.
                          Builder(
                            builder: (inside) => IconButton(
                              icon: Icon(Icons.copy,
                                  color: theme.colorScheme.onSurfaceVariant),
                              tooltip: 'Copy file',
                              onPressed: () =>
                                  _copyFile(inside, content.content),
                            ),
                          ),
                        IconButton(
                          icon: Icon(Icons.close,
                              color: theme.colorScheme.onSurfaceVariant),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    // The controls a file needs are in the file's own header: what
                    // size to read it at, and a reference to the part of it being
                    // looked at.
                    if (content != null) ...[
                      const SizedBox(height: 6),
                      _buildToolbar(context, theme, appearance),
                    ],
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
                                child: _buildBody(
                                    context, theme, appearance.fileFontScale),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
