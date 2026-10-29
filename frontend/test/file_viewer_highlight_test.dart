import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/utils/code_highlight.dart';
import 'package:pi_mobile_agent/widgets/file_browser.dart';
import 'package:pi_mobile_agent/widgets/file_viewer.dart';
import 'package:provider/provider.dart';

/// PiService stub that answers readFile with canned file contents.
class FakeFileService extends PiService {
  final Map<String, FileContent> files;
  final _events = StreamController<PiEvent>.broadcast();

  String? lastReadPath;
  int readCalls = 0;
  FileListing? listing;

  FakeFileService({required this.files});

  @override
  Future<FileListing> listFiles({String? path}) async =>
      listing ??
      FileListing(
          path: path ?? '/',
          roots: const [],
          entries: const [],
          recent: const []);

  @override
  Stream<PiEvent> get events => _events.stream;

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Future<FileContent> readFile(String path) async {
    readCalls++;
    lastReadPath = path;
    final file = files[path];
    if (file == null) throw Exception('File not found: $path');
    return file;
  }
}

FileContent _file(String content, {bool isText = true}) => FileContent(
      content: content,
      size: content.length,
      isText: isText,
      encoding: 'utf-8',
    );

const htmlPage = '''<!DOCTYPE html>
<html lang="en">
<head>
  <title>Demo</title>
  <style>.card { color: red; }</style>
</head>
<body class="page">
  <h1>Hello &amp; world</h1>
  <script>if (a < b && c > d) { console.log("<div>"); }</script>
  <a href="/x" data-id="2" onclick="go()">link</a>
</body>
</html>
''';

const csharpFile = '''using System;

public class Greeter {
  private readonly string _name;
  public int Count { get; set; } = 3;
  public void Greet() => Console.WriteLine("hi");
}
''';

const cssFile = ''':root { --brand: #3fb; }

.card {
  color: #222;
  padding: 4px 8px;
}
''';

/// Opens the viewer for [path] and lets the file load.
Future<void> _openViewer(
  WidgetTester tester, {
  required String path,
  required FileContent content,
  Brightness brightness = Brightness.dark,
}) async {
  final service = FakeFileService(files: {path: content});
  final viewModel = PiViewModel(piService: service);

  await tester.pumpWidget(
    ChangeNotifierProvider<PiViewModel>(
      create: (_) => viewModel,
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        // Opened the way the file browser opens it - through a dialog route -
        // because where the viewer sits in the route stack is part of what is
        // being tested here.
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => FileViewer(
                  filePath: path,
                  fileName: path.split('/').last,
                ),
              ),
              child: const Text('open file'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open file'));
  await tester.pumpAndSettle();
}

/// The surface the file is painted on.
Color _codeSurface(WidgetTester tester) => tester
    .widget<ColoredBox>(find
        .descendant(
            of: find.byType(FileViewer), matching: find.byType(ColoredBox))
        .first)
    .color;

/// The colour a line of the file is drawn in.
Color _codeRowColour(WidgetTester tester) {
  final row = find.ancestor(of: find.text('1'), matching: find.byType(Row));
  final rich = tester.widget<RichText>(
      find.descendant(of: row, matching: find.byType(RichText)).last);
  return (rich.text.style?.color)!;
}

/// The colour the line numbers are drawn in.
Color _gutterNumberColour(WidgetTester tester) =>
    (tester.widget<Text>(find.text('1')).style?.color)!;

/// The header's background, title colour and secondary-text colour.
(Color, Color, Color) _headerPaint(WidgetTester tester) {
  final header = tester
      .widgetList<Container>(find.byType(Container))
      .firstWhere((c) => (c.decoration as BoxDecoration?)?.border != null);
  final background = ((header.decoration as BoxDecoration).color)!;
  final title = tester.widget<Text>(find.text('app.ts'));
  final meta = tester
      .widgetList<Text>(find.byType(Text))
      .firstWhere((t) => (t.data ?? '').contains(' • '));
  return (background, title.style!.color!, meta.style!.color!);
}

/// WCAG contrast ratio between two colours: what "readable" means as a number.
double _contrast(Color a, Color b) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

  final x = luminance(a);
  final y = luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// A whole app whose appearance can be changed under a file that is open,
/// so the viewer is the same widget instance before and after the switch.
class _FlipTheme extends StatefulWidget {
  const _FlipTheme({super.key, required this.service, required this.path});

  final PiService service;
  final String path;

  @override
  State<_FlipTheme> createState() => _FlipThemeState();
}

class _FlipThemeState extends State<_FlipTheme> {
  Brightness _brightness = Brightness.dark;

  void flipToLight() => setState(() => _brightness = Brightness.light);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PiViewModel>(
      create: (_) => PiViewModel(piService: widget.service),
      child: MaterialApp(
        theme: ThemeData(brightness: _brightness),
        home: Scaffold(body: FileViewer(filePath: widget.path)),
      ),
    );
  }
}

/// The language label the viewer shows in its header.
String _headerLabel(WidgetTester tester) {
  final header = tester
      .widgetList<Text>(find.byType(Text))
      .firstWhere((t) => (t.data ?? '').contains(' • '));
  return (header.data ?? '').split(' • ').last;
}

/// Colours actually painted for the file, collected from the rendered rows.
///
/// The highlighter puts a style on a token's parent span and the text on its
/// child, so a colour only exists after inheriting down the tree.
Set<int> _paintedColours(WidgetTester tester) {
  final colours = <int>{};
  for (final element in tester.widgetList<RichText>(find.byType(RichText))) {
    void collect(TextSpan span, TextStyle? inherited) {
      final effective =
          inherited == null ? span.style : inherited.merge(span.style);
      if (span.text != null && effective?.color != null) {
        colours.add(effective!.color!.toARGB32());
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (child is TextSpan) collect(child, effective);
      }
    }

    collect(element.text as TextSpan, null);
  }
  return colours;
}

/// The colours a span tree paints, once styles are inherited down the tree.
Set<int> _spanColours(List<TextSpan> spans) {
  final colours = <int>{};
  void collect(TextSpan span, TextStyle? inherited) {
    final effective =
        inherited == null ? span.style : inherited.merge(span.style);
    if (span.text != null && effective?.color != null) {
      colours.add(effective!.color!.toARGB32());
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) collect(child, effective);
    }
  }

  for (final s in spans) {
    collect(s, null);
  }
  return colours;
}

/// The text a span tree renders, so a parse that swallows part of a file shows
/// up as a difference rather than as a page that merely looks a bit short.
String _spanText(List<TextSpan> spans) {
  final out = StringBuffer();
  void collect(TextSpan span) {
    if (span.text != null) out.write(span.text);
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) collect(child);
    }
  }

  for (final s in spans) {
    collect(s);
  }
  return out.toString();
}

/// The line numbers the viewer drew, in order.
List<String> _gutterNumbers(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .where((s) => RegExp(r'^\d+$').hasMatch(s))
    .toList();

void main() {
  group('languageForPath', () {
    test('maps the extensions a real repo contains', () {
      const expected = {
        'src/app.ts': 'typescript',
        'src/App.tsx': 'typescript',
        'web/main.js': 'javascript',
        'tooling/app.jsx': 'javascript',
        'lib/main.dart': 'dart',
        'scripts/build.py': 'python',
        'internal/server.go': 'go',
        'crates/main.rs': 'rust',
        'src/Main.java': 'java',
        'native/add.cpp': 'c++',
        'native/add.hpp': 'c++',
        'src/Program.cs': 'csharp',
        'src/Program.CS': 'csharp',
        'api/index.php': 'php',
        'script/deploy.rb': 'ruby',
        'deploy/run.sh': 'shell',
        'package.json': 'json',
        'config/app.yaml': 'yaml',
        'config/app.yml': 'yaml',
        'public/index.html': 'xml',
        'public/page.htm': 'xml',
        'styles/site.css': 'css',
        'styles/site.scss': 'css',
        'styles/site.less': 'css',
        'data/schema.sql': 'sql',
        'data/feed.xml': 'xml',
        'assets/icon.svg': 'xml',
        'app.csproj': 'xml',
        'Pages/Index.cshtml': 'xml',
        'settings/app.ini': 'ini',
        'settings/app.toml': 'ini',
        '.env': 'properties',
        'notes/CHANGELOG.diff': 'diff',
      };

      expected.forEach((path, language) {
        expect(languageForPath(path), language, reason: 'for $path');
      });
    });

    test('extension-less build files are recognised by name', () {
      expect(languageForPath('Dockerfile'), 'dockerfile');
      expect(languageForPath('app/Dockerfile.prod'), 'dockerfile');
      expect(languageForPath('Makefile'), 'makefile');
      expect(languageForPath('build/Makefile.am'), 'makefile');
      expect(languageForPath('justfile'), 'makefile');
      expect(languageForPath('/home/adam/.bashrc'), 'shell');
    });

    test('documents are recognised as prose, not code', () {
      for (final path in const [
        'README.md',
        'docs/guide.markdown',
        'notes/plain.txt',
        'CHANGELOG',
        'data/rows.csv',
      ]) {
        expect(isProsePath(path), isTrue, reason: 'for $path');
      }
      for (final path in const [
        'src/app.ts',
        'public/index.html',
        'styles/site.css',
        'package.json',
        // Not prose, just not code either: the viewer decides those by whether
        // the bytes are text, not by the name.
        'assets/logo.png',
        'no_extension_here',
      ]) {
        expect(isProsePath(path), isFalse, reason: 'for $path');
      }
    });

    test('every language it returns is one the highlighter knows', () {
      // `highlight` answers an unknown grammar by colouring nothing, so a typo
      // in the mapping would look like highlighting silently not working.
      for (final path in const [
        'a.ts',
        'b.js',
        'c.dart',
        'd.py',
        'e.go',
        'f.rs',
        'g.java',
        'h.cpp',
        'i.cs',
        'j.php',
        'k.rb',
        'l.sh',
        'm.json',
        'n.yaml',
        'o.html',
        'p.css',
        'q.sql',
        'r.ini',
        's.env',
        't.diff',
        'u.xml',
        'Dockerfile',
        'Makefile',
      ]) {
        final language = languageForPath(path);
        expect(language, isNotNull, reason: 'for $path');
        expect(highlightedSpans('x = 1', language: language!, isDark: true),
            isNotNull);
      }
    });

    test('case and windows paths do not defeat detection', () {
      expect(languageForPath(r'C:\Projects\App.TS'), 'typescript');
      expect(languageForPath(r'C:\Projects\DOCKERFILE'), 'dockerfile');
      expect(languageForPath(r'C:\Projects\PAGE.HTML'), 'xml');
    });
  });

  group('HTML colouring is not intermittent', () {
    // The shipped xml grammar hands a <style> body to subLanguage ["css", "xml"]
    // and a <script> body to ["actionscript", "javascript", "handlebars", "xml"].
    // Before `css` was registered, a page with a stylesheet in it answered with
    // nothing coloured at all while a page without one was fine - which is what
    // "it works sometimes" looked like from the phone.
    const shapes = {
      'no script or style':
          '<!DOCTYPE html>\n<html><body class="page"><h1>Hi</h1></body></html>\n',
      'with a style block':
          '<!DOCTYPE html>\n<html><body class="page"><h1>Hi</h1>\n<style>.a { color: red; }</style></body></html>\n',
      'with a comparison in a script':
          '<!DOCTYPE html>\n<html><body><h1>Hi</h1>\n<script>if (a < b && c > d) { console.log("<div>"); }</script></body></html>\n',
      'with unquoted attributes':
          '<!DOCTYPE html>\n<html><body><a href=/x data-id=2 onclick="go()">link</a></body></html>\n',
      'script and style together':
          '<!DOCTYPE html>\n<html><head><style>.a{color:red}</style></head>\n<body><script>var n = 1;</script></body></html>\n',
      'a comparison in a for loop':
          '<!DOCTYPE html>\n<html><body>\n<script>for (let i = 0; i <= n; i++) { draw("<b>"); }</script></body></html>\n',
      'a style block with a child selector':
          '<!DOCTYPE html>\n<html><head><style>.a > .b { color: red; }</style></head><body><p>x</p></body></html>\n',
    };

    shapes.forEach((label, source) {
      test(label, () {
        final spans = highlightedSpans(source, language: 'xml', isDark: true);
        final colours = <int>{};
        void collect(TextSpan t, TextStyle? inh) {
          final e = inh == null ? t.style : inh.merge(t.style);
          if (t.text != null && e?.color != null) {
            colours.add(e!.color!.toARGB32());
          }
          for (final c in t.children ?? const <InlineSpan>[]) {
            if (c is TextSpan) collect(c, e);
          }
        }

        for (final s in spans) {
          collect(s, null);
        }
        expect(colours.length, greaterThan(1),
            reason: '$label: HTML must be coloured whatever follows it');
      });
    });

    test('the language a .html file maps to is one that colours', () {
      // Mapping HTML to a grammar the highlighter does not know colours nothing,
      // which looks exactly like "the HTML colouring is broken again".
      expect(languageForPath('public/index.html'), 'xml');
      final spans = highlightedSpans(htmlPage, language: 'xml', isDark: true);
      final colours = <int>{};
      void collect(TextSpan t, TextStyle? inh) {
        final e = inh == null ? t.style : inh.merge(t.style);
        if (t.text != null && e?.color != null)
          colours.add(e!.color!.toARGB32());
        for (final c in t.children ?? const <InlineSpan>[]) {
          if (c is TextSpan) collect(c, e);
        }
      }

      for (final s in spans) {
        collect(s, null);
      }
      expect(colours.length, greaterThan(2));
    });

    test('a script body is coloured as code, not as markup', () {
      // Several colours do not prove this: markup is coloured too. The shipped
      // grammar handed <script> to the generic tag mode, so the body was read
      // as HTML - which is also why a `<` in `i <= n` answered with nothing
      // coloured at all, the parser treating it as an illegal tag.
      const script =
          'for (let i = 0; i <= items.length; i++) { f("<b>" + i); }';
      const page =
          '<!DOCTYPE html>\n<html><body>\n<script>$script</script>\n</body></html>\n';

      final insidePage =
          _spanColours(highlightedSpans(page, language: 'xml', isDark: true));
      final onItsOwn = _spanColours(
          highlightedSpans(script, language: 'javascript', isDark: true));

      expect(onItsOwn.difference(insidePage), isEmpty,
          reason: 'the same code has to be coloured the same way inside a page '
              'as it is on its own');
    });

    test('a style body is coloured as CSS, not as markup', () {
      const style = '.a > .b { color: #3fb; width: 10px; }';
      const page =
          '<!DOCTYPE html>\n<html><head><style>$style</style></head><body><p>x</p></body></html>\n';

      final insidePage =
          _spanColours(highlightedSpans(page, language: 'xml', isDark: true));
      final onItsOwn =
          _spanColours(highlightedSpans(style, language: 'css', isDark: true));

      expect(onItsOwn.difference(insidePage), isEmpty,
          reason: 'a stylesheet inside a page has to be coloured like that '
              'stylesheet on its own');
    });

    test('reading a page as HTML loses none of it', () {
      expect(
          _spanText(highlightedSpans(htmlPage, language: 'xml', isDark: true)),
          htmlPage,
          reason: 'colouring is only worth having if the file still says the '
              'same thing afterwards');
    });

    testWidgets('an HTML page is rendered with several colours',
        (WidgetTester tester) async {
      await _openViewer(
        tester,
        path: 'public/index.html',
        content: _file(htmlPage),
      );

      expect(tester.takeException(), isNull);
      expect(_paintedColours(tester).length, greaterThan(2),
          reason: 'tags, attributes and strings should not share one colour');
      expect(_headerLabel(tester), 'xml/html');
    });
  });

  group('CSS and C# are coloured', () {
    testWidgets('a stylesheet is coloured', (WidgetTester tester) async {
      await _openViewer(
        tester,
        path: 'styles/site.css',
        content: _file(cssFile),
      );

      expect(tester.takeException(), isNull);
      expect(_paintedColours(tester).length, greaterThan(1));
      expect(_headerLabel(tester), 'css');
    });

    testWidgets('a C# file is coloured', (WidgetTester tester) async {
      await _openViewer(
        tester,
        path: 'src/Program.cs',
        content: _file(csharpFile),
      );

      expect(tester.takeException(), isNull);
      expect(_paintedColours(tester).length, greaterThan(2),
          reason: 'keywords, types and strings should be distinguishable');
      expect(_headerLabel(tester), 'c#');
    });

    test('the C# grammar reaches the viewer for a real file', () {
      final spans =
          highlightedSpans(csharpFile, language: 'csharp', isDark: true);
      final colours = <int>{};
      void collect(TextSpan t, TextStyle? inh) {
        final e = inh == null ? t.style : inh.merge(t.style);
        if (t.text != null && e?.color != null)
          colours.add(e!.color!.toARGB32());
        for (final c in t.children ?? const <InlineSpan>[]) {
          if (c is TextSpan) collect(c, e);
        }
      }

      for (final s in spans) {
        collect(s, null);
      }
      expect(colours.length, greaterThan(2));
    });
  });

  group('line numbers', () {
    testWidgets('every line is numbered, in order',
        (WidgetTester tester) async {
      const source = '''
using System;

public class Greeter {
  public void Greet() { }
}
''';
      final lineCount = source.split('\n').length;

      await _openViewer(
        tester,
        path: 'src/Program.cs',
        content: _file(source),
      );

      final numbers = _gutterNumbers(tester);
      expect(numbers.take(6), ['1', '2', '3', '4', '5', '6']);
      expect(numbers.length, lineCount,
          reason: 'a blank line must still be numbered, or the numbers drift');

      // The header states the line count it numbered.
      expect(find.textContaining('$lineCount lines'), findsOneWidget);
    });

    testWidgets('numbers are right-aligned in a gutter sized to the widest',
        (WidgetTester tester) async {
      // Only the rows on screen are built, so the file has to be short enough
      // for its last number to be on screen too.
      final source = List.generate(12, (i) => 'line $i').join('\n');

      await _openViewer(
        tester,
        path: 'data/generated.txt',
        content: _file(source),
      );

      // What a gutter is for: however many digits a line number has, the file
      // text beside it always starts in the same column.
      final codeLefts = <double>{};
      for (final number in ['1', '9', '12']) {
        final row =
            find.ancestor(of: find.text(number), matching: find.byType(Row));
        // Each row is a gutter RichText followed by the line's RichText; the
        // last one is the file text.
        codeLefts.add(tester
            .getRect(
                find.descendant(of: row, matching: find.byType(RichText)).last)
            .left);
      }
      expect(codeLefts.length, 1,
          reason:
              'digits of different widths must not shift the file sideways');

      // And the gutter is measured in the code font, so the widest number fits
      // the column it was given instead of overflowing it.
      final gutterWidth = tester.getSize(find.text('12')).width;
      final painter = TextPainter(
        text: const TextSpan(
          text: '12',
          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(gutterWidth, greaterThanOrEqualTo(painter.width));
    });

    testWidgets('a plain text file is numbered too',
        (WidgetTester tester) async {
      await _openViewer(
        tester,
        path: 'notes/plain.txt',
        content: _file('first line\nsecond line\nthird line\n'),
      );

      expect(tester.takeException(), isNull);
      expect(_gutterNumbers(tester).take(3), ['1', '2', '3']);
      // Prose is not coloured just because something in it looked like code.
      expect(_headerLabel(tester), 'plain text');
    });

    test('splitSpansByLine keeps the text of every line', () {
      const source = 'let a = "one\nmulti";\nlet b = 2;\n';
      final spans =
          highlightedSpans(source, language: 'javascript', isDark: true);
      final lines = splitSpansByLine(spans);

      expect(lines.length, source.split('\n').length);

      String joined(int i) {
        final sb = StringBuffer();
        for (final s in lines[i]) {
          sb.write(s.text);
        }
        return sb.toString();
      }

      for (var i = 0; i < lines.length; i++) {
        expect(joined(i), source.split('\n')[i], reason: 'line ${i + 1}');
      }
    });

    test('a token that spans lines keeps its colours on every line', () {
      // Cutting a file into lines must not cut a token in half: a block comment
      // is one token, so every line of it has to stay a comment line.
      const source = '/* first\n   second */\nint x = 2;\n';
      final spans = highlightedSpans(source, language: 'c++', isDark: true);
      final lines = splitSpansByLine(spans);

      bool colouredAt(int i) => lines[i].any((s) => s.style?.color != null);
      expect(colouredAt(0), isTrue);
      expect(colouredAt(1), isTrue,
          reason: 'the second half of a block comment must stay coloured');
    });
  });

  group('copying', () {
    /// Records what the app tried to put on the clipboard, and can be made to
    /// refuse - which is what the browser does on a plain http origin.
    void fakeClipboard(void Function(String text) handle) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          handle((call.arguments as Map)['text'] as String? ?? '');
        }
        return null;
      });
    }

    testWidgets('copying a file gives the file, without line numbers',
        (WidgetTester tester) async {
      const source = 'let a = 1;\nlet b = 2;\n';
      await _openViewer(
        tester,
        path: 'src/app.js',
        content: _file(source),
      );

      String? copied;
      fakeClipboard((text) => copied = text);

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();

      expect(copied, source);
      expect(copied, isNot(contains('1 let')));

      expect(find.text('Copied file'), findsOneWidget,
          reason: 'a button that copies in silence is a button nobody trusts');
      // And it has to be inside the dialog. A SnackBar handed to the app's own
      // Scaffold is painted behind this route, which on a phone is behind the
      // dialog itself - a confirmation that exists and cannot be seen.
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Copied file'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a copy the browser refuses says so',
        (WidgetTester tester) async {
      await _openViewer(
        tester,
        path: 'src/app.js',
        content: _file('let a = 1;\n'),
      );

      // Exactly what the engine raises when the browser has no Clipboard API -
      // a plain http origin, which is where this app runs.
      fakeClipboard((_) => throw PlatformException(code: 'copy_fail'));

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason:
              'a refused copy is an expected outcome, not an exception left '
              'lying around');
      expect(find.textContaining('Copy failed'), findsOneWidget);
    });
  });

  group('fallbacks', () {
    testWidgets(
        'a file with an unknown extension is still offered to the '
        'highlighter instead of being shown plain',
        (WidgetTester tester) async {
      await _openViewer(
        tester,
        path: 'misc/mysteryfile',
        content: _file('def hello():\n    print("world")\n'),
      );

      expect(tester.takeException(), isNull);
      expect(_headerLabel(tester), 'guessed');
    });

    testWidgets('a file too large to parse is shown plain instead of stalling',
        (WidgetTester tester) async {
      // Highlighting parses on the UI thread; a whole source file of this size
      // would freeze the dialog, so it must fall back rather than try.
      final huge =
          List.generate(20000, (i) => 'const value$i = $i;').join('\n');
      expect(huge.length, greaterThan(120 * 1024));

      await _openViewer(
        tester,
        path: 'generated/data.js',
        content: _file(huge),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining(RegExp(r'not coloured \(too large\)')),
          findsOneWidget);
      expect(_gutterNumbers(tester).take(3), ['1', '2', '3']);
    });

    testWidgets('a binary file is not coloured', (WidgetTester tester) async {
      await _openViewer(
        tester,
        path: 'assets/blob.dat',
        content: _file('\u0000\u0001\u0002payload', isText: false),
      );

      expect(tester.takeException(), isNull);
      expect(_headerLabel(tester), 'binary');
    });

    testWidgets('a light theme gets the light palette',
        (WidgetTester tester) async {
      await _openViewer(
        tester,
        path: 'app.js',
        content: _file('const x = 1;\n'),
        brightness: Brightness.light,
      );

      expect(tester.takeException(), isNull);
      expect(_paintedColours(tester).length, greaterThan(1));
    });
  });

  group('reading', () {
    testWidgets('the file is read from the path it was opened with',
        (WidgetTester tester) async {
      const path = 'src/deep/nested/file.dart';
      final service = FakeFileService(files: {path: _file('void main() {}')});

      await tester.pumpWidget(
        ChangeNotifierProvider<PiViewModel>(
          create: (_) => PiViewModel(piService: service),
          child: MaterialApp(
            home: Scaffold(body: FileViewer(filePath: path)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.readCalls, 1);
      expect(service.lastReadPath, path);
    });

    testWidgets('a failed read reports the error instead of a blank panel',
        (WidgetTester tester) async {
      final service = FakeFileService(files: {});

      await tester.pumpWidget(
        ChangeNotifierProvider<PiViewModel>(
          create: (_) => PiViewModel(piService: service),
          child: MaterialApp(
            home: Scaffold(body: FileViewer(filePath: 'gone.txt')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Error loading file'), findsOneWidget);
      expect(find.textContaining('gone.txt'), findsWidgets);
    });
  });

  group('opening a file from the browser', () {
    testWidgets('the file it opens is coloured', (WidgetTester tester) async {
      // The path a person actually takes: the list, a tap on a file, the viewer
      // that comes back. Testing the viewer on its own leaves that path untested
      // - and the path is where a wrong path or a wrong name would show up.
      const source = 'export const greet = (name: string) => "hi " + name;\n'
          '// a comment\nfunction id(x: number): number { return x; }\n';
      final service = FakeFileService(files: {'/src/app.ts': _file(source)})
        ..listing = FileListing(
          path: '/src',
          roots: const [],
          entries: [
            DirEntry(
                name: 'app.ts',
                path: '/src/app.ts',
                isDirectory: false,
                size: source.length),
          ],
          recent: const [],
        );

      await tester.pumpWidget(
        ChangeNotifierProvider<PiViewModel>(
          create: (_) => PiViewModel(piService: service),
          child: const MaterialApp(home: Scaffold(body: FileBrowser())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('app.ts'));
      await tester.pumpAndSettle();

      expect(find.byType(FileViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(_paintedColours(tester).length, greaterThan(2),
          reason: 'a file opened by tapping it in the list has to be coloured '
              'like one opened any other way');
    });
  });

  group('the colours follow the appearance the app is in', () {
    testWidgets('the file reads on the surface it is painted on',
        (WidgetTester tester) async {
      for (final brightness in Brightness.values) {
        await _openViewer(
          tester,
          path: 'src/app.ts',
          content: _file('const n = 1;\n// a note\nexport default n;\n'),
          brightness: brightness,
        );

        final surface = _codeSurface(tester);
        final text = _codeRowColour(tester);
        expect(_contrast(text, surface), greaterThanOrEqualTo(4.5),
            reason:
                '$brightness: the file text must read on its own background');

        final numbers = _gutterNumberColour(tester);
        expect(_contrast(numbers, surface), greaterThanOrEqualTo(2.0),
            reason:
                '$brightness: line numbers are secondary, but not invisible');
      }
    });

    testWidgets('light and dark are not the same colours',
        (WidgetTester tester) async {
      await _openViewer(
        tester,
        path: 'src/app.ts',
        content: _file('const n = 1;\n'),
        brightness: Brightness.dark,
      );
      final dark = _codeSurface(tester);

      await _openViewer(
        tester,
        path: 'src/app.ts',
        content: _file('const n = 1;\n'),
        brightness: Brightness.light,
      );
      final light = _codeSurface(tester);

      expect(dark, isNot(light),
          reason:
              'a viewer that paints the same surface in both appearances is '
              'following its own palette, not the app');
    });

    testWidgets(
        'a file already open re-colours when the app changes appearance',
        (WidgetTester tester) async {
      final key = GlobalKey<_FlipThemeState>();
      await tester.pumpWidget(_FlipTheme(
        key: key,
        service:
            FakeFileService(files: {'src/app.ts': _file('const n = 1;\n')}),
        path: 'src/app.ts',
      ));
      await tester.pumpAndSettle();

      final before = _codeSurface(tester);
      final beforeText = _codeRowColour(tester);

      key.currentState!.flipToLight();
      await tester.pumpAndSettle();

      expect(_codeSurface(tester), isNot(before),
          reason:
              'the surface was chosen once, at load, and kept after the switch');
      expect(_codeRowColour(tester), isNot(beforeText));
      expect(_contrast(_codeRowColour(tester), _codeSurface(tester)),
          greaterThanOrEqualTo(4.5));
    });

    testWidgets('the header reads on its own background in both appearances',
        (WidgetTester tester) async {
      for (final brightness in Brightness.values) {
        await _openViewer(
          tester,
          path: 'src/app.ts',
          content: _file('const n = 1;\n'),
          brightness: brightness,
        );

        final (background, title, meta) = _headerPaint(tester);
        expect(_contrast(title, background), greaterThanOrEqualTo(4.5),
            reason: '$brightness: the file name is the first thing read here');
        expect(_contrast(meta, background), greaterThanOrEqualTo(3.0),
            reason:
                '$brightness: the size and language line is not decoration');
      }
    });
  });
}
