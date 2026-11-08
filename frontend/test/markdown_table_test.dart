import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/utils/dracula_scheme.dart';
import 'package:pi_mobile_agent/utils/markdown_tables.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';

/// A table in a chat reply is the one part of Markdown that is laid out by the
/// width it is given rather than by what is in it, which on a phone meant every
/// column got the same 73px and a reply that said six things came out a screen
/// and a half tall. These are the two things that replaced it: the split that
/// lets a table be asked how wide it needs to be, and the width it is given.
const _wideTable = '''**Here is what the run touched:**

| file | what changed | lines | status | notes about it |
| --- | --- | --- | --- | --- |
| `lib/widgets/chat_bubble.dart` | added the compact branch and the preview helper | 118 | done | one text run per line, wrapped rather than truncated |
| `lib/utils/chat_palette.dart` | added the output preview colour, measured on the bubble | 24 | done | raised only where the reply needs the raise |
| `lib/screens/home_screen.dart` | menu copy for both states of the switch | 9 | done | the old copy said commands were hidden |
''';

/// Three short columns, which is the table that fits and must not be made to
/// scroll for no reason.
const _narrowTable = '''| file | lines | status |
| --- | --- | --- |
| a.dart | 118 | done |
| b.dart | 24 | done |
''';

TextStyle _body() => const TextStyle(fontSize: 13, color: Colors.black);
TextStyle _code() =>
    const TextStyle(fontSize: 13, fontFamily: 'JetBrainsMono', color: Colors.black);

const _padding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);

double _width(String source) => tablePreferredWidth(
      source,
      bodyStyle: _body(),
      codeStyle: _code(),
      cellPadding: _padding,
    );

void main() {
  group('splitting a reply at its tables', () {
    test('a table comes out as its own piece, and the text around it stays',
        () {
      final segments = splitMarkdownTables('''before the table

$_wideTable

after the table''');

      expect(segments.map((s) => s.isTable), [false, true, false]);
      expect(segments[0].source, contains('before the table'));
      expect(segments[1].source, startsWith('| file'));
      expect(segments[1].source, contains('| 118 |'));
      expect(segments[2].source, contains('after the table'));
    });

    test('a table inside a fenced block is code, and stays code', () {
      final segments = splitMarkdownTables('''```markdown
| file | lines |
| --- | --- |
| a.dart | 1 |
```''');

      expect(segments.where((s) => s.isTable), isEmpty);
      expect(segments.single.source, contains('```markdown'));
    });

    test('a table inside a list item belongs to the list item', () {
      // Indented, which is the parser's own signal that it is inside something.
      // Pulling it out would render it as a top-level table and lose the list
      // it was a part of.
      final segments = splitMarkdownTables('''- first item

  | file | lines |
  | --- | --- |
  | a.dart | 1 |

- second item''');

      expect(segments.where((s) => s.isTable), isEmpty);
    });

    test('a table with no blank line before it is the end of a paragraph', () {
      // The parser does not read that as a table either, and a splitter that
      // invented one would be adding structure the reply does not have.
      final segments = splitMarkdownTables('''prose that runs on
| file | lines |
| --- | --- |
| a.dart | 1 |''');

      expect(segments.where((s) => s.isTable), isEmpty);
    });

    test('a reply with no table is one piece, unchanged', () {
      const text = 'just a paragraph\n\nand another';
      final segments = splitMarkdownTables(text);

      expect(segments, hasLength(1));
      expect(segments.single.isTable, isFalse);
      expect(segments.single.source, contains('just a paragraph'));
      expect(segments.single.source, contains('and another'));
    });

    test('two tables are two tables', () {
      final segments = splitMarkdownTables('''$_narrowTable

some prose

$_narrowTable''');

      expect(segments.map((s) => s.isTable), [true, false, true]);
    });
  });

  group('the columns of a table', () {
    test('the pipes at the ends of a row are the row, not a column', () {
      // Splitting a row as it is written invents an empty column at the end of
      // every table, which is a column of nothing that still takes width.
      // (What [tableColumns] returns is columns: one list per column.)
      final columns = tableColumns('| a | b |');
      expect(columns.length, 2);
      expect(columns.map((c) => c.map((cell) => cell.trim()).toList()),
          [
            ['a'],
            ['b']
          ]);
    });

    test('a pipe inside a cell is the cell’s, not a column break', () {
      final columns = tableColumns(r'| grep foo \| bar | sed |');
      expect(columns.length, 2);
      expect(columns.first.single.trim(), r'grep foo | bar');
    });

    test('the delimiter row is not a row of data', () {
      final columns = tableColumns(_narrowTable);
      expect(columns.first.length, 3); // header and two rows
      expect(columns.first, isNot(contains(matches(r'^[\s:|-]+\$'))));
    });
  });

  group('the width a table asks for', () {
    test('a table of prose asks for more than a phone bubble has', () {
      expect(_width(_wideTable), greaterThan(358));
    });

    test('every column has a floor under it', () {
      // A table of short columns is not a table of one-character columns.
      final width = _width('''| a | b | c | d | e |
| --- | --- | --- | --- | --- |
| 1 | 2 | 3 | 4 | 5 |''');
      expect(width, greaterThanOrEqualTo(5 * 96));
    });

    test('a cell that is code is measured as code', () {
      // A column of paths has to be measured in the face those paths are drawn
      // in, which is a monospace one and wider than the body face. In a test
      // run no font family resolves to a real font, so what is measurable here
      // is that the code style is the one used - a code style with different
      // metrics gives a different number, and that is the assertion.
      const paths = '''| `lib/widgets/chat_bubble.dart` |
| --- |
| `lib/utils/markdown_tables.dart` |''';

      final asCode = tablePreferredWidth(paths,
          bodyStyle: const TextStyle(fontSize: 8),
          codeStyle: const TextStyle(fontSize: 16),
          cellPadding: _padding);
      final asProse = tablePreferredWidth(paths,
          bodyStyle: const TextStyle(fontSize: 16),
          codeStyle: const TextStyle(fontSize: 8),
          cellPadding: _padding);

      expect(asCode, greaterThan(asProse));
    });

    test('a table that fits asks for nothing it cannot be given', () {
      expect(_width(_narrowTable), lessThan(358));
    });

    test('the answer is bounded, however absurd the table is', () {
      final absurd = [
        '| column |',
        '| --- |',
        for (var i = 0; i < 40; i++)
          '| ${'a' * 120} |',
      ].join('\n');

      expect(_width(absurd), lessThanOrEqualTo(4000));
    });
  });

  group('a table in a bubble at a phone width', () {
    Future<void> pumpBubble(WidgetTester tester, String content) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: Dracula.darkScheme(),
          brightness: Brightness.dark,
        ),
        home: Scaffold(
          body: ListView(children: [
            ChatBubble(
              message: PiMessage(
                id: 'table-1',
                role: 'assistant',
                content: content,
                timestamp: DateTime(2026),
              ),
            ),
          ]),
        ),
      ));
      await tester.pump();
    }

    testWidgets('a table with no other markup in it is still a table',
        (tester) async {
      // It used to be a wall of `|` characters: the reply had the structure and
      // the app only rendered Markdown when something else in the text gave it
      // away.
      await pumpBubble(tester, _narrowTable);

      expect(find.byType(Table), findsOneWidget);
      expect(find.text('lib/widgets/chat_bubble.dart'), findsNothing);
      expect(find.textContaining('| file | lines |', findRichText: true),
          findsNothing,
          reason: 'the source of the table is not what is on screen');
    });

    testWidgets('a table that does not fit is given the width it asked for, '
        'sideways', (tester) async {
      await pumpBubble(tester, _wideTable);

      expect(find.byType(Table), findsOneWidget);
      final scroller = find.descendant(
          of: find.byType(ChatBubble),
          matching: find.byType(SingleChildScrollView));
      expect(scroller, findsWidgets,
          reason: 'a table wider than the bubble scrolls sideways rather than '
              'being crushed into it');
      final sideways = tester
          .widgetList<SingleChildScrollView>(scroller)
          .any((w) => w.scrollDirection == Axis.horizontal);
      expect(sideways, isTrue);

      final cell = tester.getSize(find.byType(TableCell).first);
      expect(cell.width, greaterThanOrEqualTo(120),
          reason: 'the whole point: 73px is about ten characters to a line, '
              'which is not a column of anything');
    });

    testWidgets('a table that fits is not made to scroll', (tester) async {
      await pumpBubble(tester, _narrowTable);

      final bubble = tester.getRect(find.byType(ChatBubble));
      final table = tester.getRect(find.byType(Table).first);
      expect(table.width, lessThanOrEqualTo(bubble.width),
          reason: 'a table that fits is laid out as any other block of the '
              'reply, and nothing here changed what that looks like');
      expect(
          tester
              .widgetList<SingleChildScrollView>(find.descendant(
                  of: find.byType(ChatBubble),
                  matching: find.byType(SingleChildScrollView)))
              .where((w) => w.scrollDirection == Axis.horizontal),
          isEmpty);
    });

    testWidgets('the rest of the reply is still there, and still in order',
        (tester) async {
      await pumpBubble(tester,
          'Before the table.\n\n$_wideTable\n\nAfter the table.');

      expect(find.textContaining('Before the table.', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('After the table.', findRichText: true),
          findsOneWidget);

      final before = tester.getTopLeft(find.textContaining('Before the table',
              findRichText: true))
          .dy;
      final table = tester.getTopLeft(find.byType(Table).first).dy;
      final after = tester.getTopLeft(find.textContaining('After the table',
              findRichText: true))
          .dy;
      expect(before, lessThan(table));
      expect(table, lessThan(after));
    });

    testWidgets('a six-row table is not a screen and a half of table',
        (tester) async {
      await pumpBubble(tester, _wideTable);

      final table = tester.getSize(find.byType(Table).first);
      expect(table.height, lessThan(700),
          reason: 'it used to be 1489px tall, which is the whole reason '
              'scrolling past one was slow - the work of a scroll is '
              'proportional to how much there is of it');
    });

    testWidgets('the cells keep the markup they were written with',
        (tester) async {
      await pumpBubble(tester, _wideTable);

      // A path in a cell is still code: the monospace face and its own
      // background, which is what makes a table of paths readable.
      final rich = tester
          .widgetList<RichText>(find.descendant(
              of: find.byType(Table), matching: find.byType(RichText)))
          .expand((r) => _spanTexts(r.text));
      expect(rich, contains('lib/widgets/chat_bubble.dart'),
          reason: 'the backticks are markup, not text');

      final mono = tester
          .widgetList<RichText>(find.descendant(
              of: find.byType(Table), matching: find.byType(RichText)))
          .any((r) => _hasMonospaceSpan(r.text));
      expect(mono, isTrue);
    });
  });
}

Iterable<String> _spanTexts(InlineSpan span) {
  final out = <String>[];
  span.visitChildren((child) {
    if (child is TextSpan) out.add(child.toPlainText());
    return true;
  });
  return out;
}

bool _hasMonospaceSpan(InlineSpan span) {
  var found = false;
  span.visitChildren((child) {
    if (child is TextSpan &&
        child.style?.fontFamily == 'JetBrainsMono') {
      found = true;
    }
    return true;
  });
  return found;
}
