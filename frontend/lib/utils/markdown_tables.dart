import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A Markdown reply is one document, but a table in it is not text: it is a
/// grid, and a grid gets laid out by the width it is given.
///
/// Given a phone bubble, `Table` asks every column what it would like - and a
/// column with a sentence in it answers "as much as you have", because that is
/// what its intrinsic width measures *under the available width*. Four columns
/// giving the same answer share the bubble equally, so a three-character column
/// and a ninety-character one are both 73px wide, the long ones wrap into eight
/// lines each, and a table that says six things comes out a screen and a half
/// tall. That is what a table in this app looked like, and it is why scrolling
/// past one was slow: the work is proportional to the height.
///
/// So the tables are split out of the document and asked how wide they actually
/// need to be - measured from their own text, not from the space left over -
/// and given that width. When the bubble is wider than the table needs, nothing
/// here changes anything about how it looks. When it is not, the table scrolls
/// sideways instead of being crushed, which is what every other narrow reader
/// does, and what this app already does for a code block.
class MarkdownSegment {
  const MarkdownSegment({required this.source, required this.isTable});

  /// The Markdown source of this piece of the reply.
  final String source;

  /// Whether it is a table, which is the only thing that needs its own width.
  final bool isTable;
}

/// A GitHub-style table line: starts and ends with a pipe.
final RegExp _tableRow = RegExp(r'^ {0,3}\|.*\|\s*$');

/// The `|---|:--:|` line that says a table header has been read. A table is
/// only a table with one, and only after a blank line.
final RegExp _tableDelimiter = RegExp(r'^ {0,3}\|[\s:|-]+\|\s*$');

final RegExp _fence = RegExp(r'^\s*```');

/// Split a reply into the text and the tables, so each can be laid out as what
/// it is.
///
/// Only tables at the top level of the document are split out: an indented one
/// belongs to a list item or a blockquote and has to stay inside it to render
/// as that thing at all. A table inside a fenced block is code, not a table.
///
/// This is deliberately a line-level split rather than a re-parse of the
/// document. The Markdown parser is what it is; what is wrong is the width it
/// was handed, and a splitter that only cuts at the blank line before a table
/// header cannot mis-read anything the parser would not have read the same way.
List<MarkdownSegment> splitMarkdownTables(String source) {
  final lines = source.split('\n');
  final segments = <MarkdownSegment>[];
  final text = StringBuffer();
  var inFence = false;

  void flushText() {
    if (text.isEmpty) return;
    segments.add(MarkdownSegment(source: text.toString(), isTable: false));
    text.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      text.writeln(line);
      i++;
      continue;
    }
    if (inFence) {
      text.writeln(line);
      i++;
      continue;
    }

    final startsTable = _tableRow.hasMatch(line) &&
        i + 1 < lines.length &&
        _tableDelimiter.hasMatch(lines[i + 1]) &&
        _blankBefore(lines, i);

    if (!startsTable) {
      text.writeln(line);
      i++;
      continue;
    }

    var end = i;
    while (end < lines.length && _tableRow.hasMatch(lines[end])) {
      end++;
    }
    flushText();
    segments.add(MarkdownSegment(
        source: lines.skip(i).take(end - i).join('\n'), isTable: true));
    i = end;
  }

  flushText();

  // A run of blank lines between two blocks is the space between them, not a
  // block. Kept as a piece of its own it is an empty MarkdownBody where a gap
  // was meant; joined to the block it follows, it is that gap.
  final joined = <MarkdownSegment>[];
  for (final segment in segments) {
    if (segment.source.trim().isEmpty && joined.isNotEmpty) {
      joined[joined.length - 1] = MarkdownSegment(
          source: '${joined.last.source}${segment.source}',
          isTable: joined.last.isTable);
    } else {
      joined.add(segment);
    }
  }
  return joined;
}

bool _blankBefore(List<String> lines, int index) {
  if (index == 0) return true;
  // A table that is not preceded by a blank line is not a table to the parser
  // either - it is the tail of a paragraph. Splitting there would invent a
  // structure the document does not have.
  if (lines[index - 1].trim().isNotEmpty) return false;

  // A blank line is only "top level" if what sits above it is not a list item.
  // A table indented under a bullet belongs to that bullet; lifting it out
  // would render it beside the list rather than inside it.
  for (var i = index - 1; i >= 0; i--) {
    if (lines[i].trim().isEmpty) continue;
    return !_listItem.hasMatch(lines[i]);
  }
  return true;
}

/// The line a table would have to be under to not be a table of its own.
final RegExp _listItem = RegExp(r'^\s*([-*+]|\d+\.)\s');

/// The columns of a table, as their raw cell text.
///
/// Raw, because the width a column needs depends on what is in it: a cell of
/// `code` is measured in a monospace face, which is wider than the same words
/// in the body face, and a column of them has to be wider.
List<List<String>> tableColumns(String source) {
  final rows = <List<String>>[];
  for (final line in source.split('\n')) {
    if (!_tableRow.hasMatch(line)) continue;
    final trimmed = line.trim();
    final cells = _splitCells(trimmed);
    if (cells.every((c) => RegExp(r'^[\s:|-]+$').hasMatch(c))) continue;
    rows.add(cells);
  }

  final columns = rows.isEmpty
      ? <List<String>>[]
      : List.generate(rows.first.length, (_) => <String>[]);
  for (final row in rows) {
    for (var c = 0; c < columns.length; c++) {
      columns[c].add(c < row.length ? row[c] : '');
    }
  }
  return columns;
}

/// Split a row on the pipes that are not escaped.
///
/// The outer pipes are the row's own brackets, not a separator: splitting a row
/// as it is written invents an empty column at the end of every table.
List<String> _splitCells(String row) {
  var body = row;
  if (body.startsWith('|')) body = body.substring(1);
  if (body.endsWith('|')) body = body.substring(0, body.length - 1);

  final out = <String>[];
  final buffer = StringBuffer();
  var escaped = false;
  for (var i = 0; i < body.length; i++) {
    final ch = body[i];
    if (escaped) {
      buffer.write(ch);
      escaped = false;
      continue;
    }
    if (ch == r'\') {
      escaped = true;
      continue;
    }
    if (ch == '|') {
      out.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(ch);
  }
  out.add(buffer.toString());
  return out;
}

/// A cell that is one span of code, which is the common case for a path or a
/// command in a table, and the one a proportional font would measure too narrow.
bool isCodeCell(String raw) => RegExp(r'^\s*`[^`]+`\s*$').hasMatch(raw);

/// The text a cell is made of, with its inline markup dropped: `**bold**` is
/// measured as the word it is wrapped in, which is what a column has to hold.
String plainCellText(String raw) {
  var text = raw.trim();
  text = text.replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (m) => m.group(1)!);
  text = text.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1)!);
  text = text
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!);
  text = text.replaceAll(RegExp(r'[*_]'), '');
  return text.trim();
}

/// How wide a table wants to be: the width that lets every column hold its
/// longest cell on one line, with a floor under each column so a table of
/// single characters is still a table of readable columns.
///
/// Measured with [TextPainter] on the strings, at the style the cells are drawn
/// in. That is cheaper than what it replaces - `Table` measures every cell, in
/// every column, for its intrinsic widths, on every layout pass - and it is
/// done once per reply, inside the body that is already cached.
double tablePreferredWidth(
  String source, {
  required TextStyle bodyStyle,
  required TextStyle codeStyle,
  required EdgeInsets cellPadding,
  double floorPerColumn = 96,
  double maxWidth = 4000,
}) {
  final columns = tableColumns(source);
  if (columns.isEmpty) return 0;

  var total = 0.0;
  for (final cells in columns) {
    var widest = 0.0;
    for (final raw in cells) {
      final style = isCodeCell(raw) ? codeStyle : bodyStyle;
      final painter = TextPainter(
        text: TextSpan(text: plainCellText(raw), style: style),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }
    final withPadding = widest + cellPadding.left + cellPadding.right;
    total += withPadding < floorPerColumn ? floorPerColumn : withPadding;
  }

  return total > maxWidth ? maxWidth : total;
}

/// A table, given the width it asked for.
///
/// [tableBuilder] renders the table at the width it is handed, which is the point: the
/// child is built by the caller because the caller knows how a table is drawn
/// here, and all this knows is how wide one needs to be.
class MarkdownTableFrame extends StatelessWidget {
  const MarkdownTableFrame({
    super.key,
    required this.preferredWidth,
    required this.tableBuilder,
  });

  /// How much wider than the space it was given a table is allowed to be.
  ///
  /// A bound, not a licence: the width a table actually wants is usually several
  /// screens of prose, and a reader is not going to swipe through that. Two and
  /// a half times the bubble is about a swipe and a half on a phone, which is a
  /// thing a person will do, and enough to take a column from 73px to something
  /// they can read. Past the bound the columns share what they were given -
  /// which is what happens today - but they share it across more width.
  static const double _maxWidthMultiple = 2.5;

  /// The width the table's own text asked for, from [tablePreferredWidth],
  /// computed when the reply was built - not on every layout pass. A measurement
  /// of the whole table repeated on each frame is the cost this whole file
  /// exists to avoid.
  final double preferredWidth;

  final Widget Function(BuildContext context, double width) tableBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return tableBuilder(context, preferredWidth);
        }
        final available = constraints.maxWidth;
        final given = preferredWidth <= available
            ? available
            : (preferredWidth < available * _maxWidthMultiple
                ? preferredWidth
                : available * _maxWidthMultiple);
        if (given <= available) {
          // The bubble is wider than the table needs. It is laid out as any
          // other block of the reply, and nothing about this file has changed
          // what that looks like.
          return tableBuilder(context, available);
        }
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: given,
              child: tableBuilder(context, given),
            ),
          ),
        );
      },
    );
  }
}
