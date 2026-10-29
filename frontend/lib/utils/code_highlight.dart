import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/highlight_core.dart' show Highlight, Node;
import 'package:highlight/languages/bash.dart' show bash;
import 'package:highlight/languages/cpp.dart' show cpp;
import 'package:highlight/languages/cs.dart' show cs;
import 'package:highlight/languages/css.dart' show css;
import 'package:highlight/languages/dart.dart' show dart;
import 'package:highlight/languages/diff.dart' show diff;
import 'package:highlight/languages/dockerfile.dart' show dockerfile;
import 'package:highlight/languages/go.dart' show go;
import 'package:highlight/languages/http.dart' show http;
import 'package:highlight/languages/ini.dart' show ini;
import 'package:highlight/languages/java.dart' show java;
import 'package:highlight/languages/javascript.dart' show javascript;
import 'package:highlight/languages/json.dart' show json;
import 'package:highlight/languages/makefile.dart' show makefile;
import 'package:highlight/languages/php.dart' show php;
import 'package:highlight/languages/plaintext.dart' show plaintext;
import 'package:highlight/languages/properties.dart' show properties;
import 'package:highlight/languages/python.dart' show python;
import 'package:highlight/languages/ruby.dart' show ruby;
import 'package:highlight/languages/rust.dart' show rust;
import 'package:highlight/languages/shell.dart' show shell;
import 'package:highlight/languages/sql.dart' show sql;
import 'package:highlight/languages/typescript.dart' show typescript;
import 'package:highlight/languages/yaml.dart' show yaml;

import 'xml_grammar.dart' show xml;

/// Syntax highlighting for chat bubbles.
///
/// Two performance rules this file exists to enforce:
///
/// 1. `highlight`'s `autoDetection` parses the source once *per registered
///    language*. The stock `package:highlight/highlight.dart` registers ~190
///    grammars, so every bare ``` fence and every tool result used to be
///    parsed ~190 times. Only the languages Pi realistically emits are
///    registered here; any other fence falls back to plain monospace text.
/// 2. `flutter_highlight`'s `HighlightView` calls `highlight.parse()` inside
///    `build()`, so scrolling a chat re-highlighted every visible code block on
///    every frame. [HighlightedCode] parses once per (source, language, theme)
///    and reuses the resulting `TextSpan` tree.

/// Languages offered to the highlighter. Aliases declared by each grammar
/// (`sh`/`zsh`, `ts`, `py`, `c++`, …) are registered along with the name.
///
/// The list is also a constraint on the grammars themselves: the HTML grammar
/// hands the body of a `<style>` block to `css` and the body of a `<script>`
/// block to `javascript`, so both are here for the markup grammar to reach as
/// well as for their own files. A sub-language a grammar asks for that this map
/// does not contain colours nothing - which is what "HTML colouring works
/// sometimes" looked like from the phone. The grammar registered as `xml` is a
/// corrected copy of the shipped one: see `xml_grammar.dart`.
final Highlight _highlighter = Highlight()
  ..registerLanguages({
    'bash': bash,
    'shell': shell,
    'c++': cpp,
    'csharp': cs,
    'css': css,
    'dart': dart,
    'diff': diff,
    'dockerfile': dockerfile,
    'go': go,
    'http': http,
    'ini': ini,
    'java': java,
    'javascript': javascript,
    'json': json,
    'makefile': makefile,
    'php': php,
    'plaintext': plaintext,
    'properties': properties,
    'python': python,
    'ruby': ruby,
    'rust': rust,
    'sql': sql,
    'typescript': typescript,
    'xml': xml,
    'yaml': yaml,
  });

const _darkTheme = atomOneDarkTheme;
const _lightTheme = atomOneLightTheme;

/// Rendered span trees, keyed by source + language + theme. Bounded LRU so a
/// long chat cannot grow memory without limit.
final LinkedHashMap<String, List<TextSpan>> _spanCache =
    LinkedHashMap<String, List<TextSpan>>();
const int _maxCachedBlocks = 200;

/// Highlights [source] and returns reusable text spans.
///
/// When [language] is null the language is auto-detected, which is only cheap
/// because of the deliberately small language set above.
List<TextSpan> highlightedSpans(
  String source, {
  String? language,
  required bool isDark,
}) {
  final key =
      '${isDark ? 'd' : 'l'}|${language ?? 'auto'}|${source.length}|${source.hashCode}';

  final cached = _spanCache.remove(key);
  if (cached != null) {
    _spanCache[key] = cached;
    return cached;
  }

  final result = language == null
      ? _highlighter.parse(source, autoDetection: true)
      : _highlighter.parse(source, language: language);

  final spans = <TextSpan>[
    for (final node in result.nodes ?? const <Node>[])
      _toTextSpan(node, isDark ? _darkTheme : _lightTheme),
  ];

  while (_spanCache.length >= _maxCachedBlocks) {
    _spanCache.remove(_spanCache.keys.first);
  }
  _spanCache[key] = spans;
  return spans;
}

TextSpan _toTextSpan(Node node, Map<String, TextStyle> theme) {
  final style = node.className == null ? null : theme[node.className!];
  if (node.value != null) {
    return TextSpan(text: node.value, style: style);
  }
  return TextSpan(
    style: style,
    children: [
      for (final child in node.children ?? const <Node>[]) _toTextSpan(child, theme),
    ],
  );
}

/// Drop cached highlight results (e.g. after the chat is cleared).
void clearHighlightCache() => _spanCache.clear();

/// File extension (or file name, for extension-less files like `Dockerfile`) to
/// a language registered above. Used by the file viewer to colour a file it has
/// no fence info for - a chat fence states its language, a file only has a name.
///
/// Values are deliberately restricted to keys in [_highlighter]: `highlight`
/// answers an unknown language by falling back to plain text, so an unmapped
/// name here would silently colour nothing.
const Map<String, String> _languageByExtension = {
  'js': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'dart': 'dart',
  'py': 'python',
  'pyw': 'python',
  'go': 'go',
  'rs': 'rust',
  'java': 'java',
  'kt': 'java',
  'groovy': 'java',
  'c': 'c++',
  'h': 'c++',
  'cpp': 'c++',
  'cc': 'c++',
  'cxx': 'c++',
  'hpp': 'c++',
  'hh': 'c++',
  'cs': 'csharp',
  'cshtml': 'xml',
  'csproj': 'xml',
  'php': 'php',
  'rb': 'ruby',
  'sh': 'shell',
  'bash': 'shell',
  'zsh': 'shell',
  'fish': 'shell',
  'json': 'json',
  'jsonc': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
  'xml': 'xml',
  'xsl': 'xml',
  'svg': 'xml',
  'plist': 'xml',
  'html': 'xml',
  'htm': 'xml',
  'xhtml': 'xml',
  'css': 'css',
  'scss': 'css',
  'sass': 'css',
  'less': 'css',
  'sql': 'sql',
  'ini': 'ini',
  'toml': 'ini',
  'conf': 'ini',
  'env': 'properties',
  'properties': 'properties',
  'diff': 'diff',
  'patch': 'diff',
};

/// Names of extension-less files the highlighter has a grammar for.
const Map<String, String> _languageByFileName = {
  'dockerfile': 'dockerfile',
  'makefile': 'makefile',
  'gnumakefile': 'makefile',
  'justfile': 'makefile',
  '.bashrc': 'shell',
  '.bashprofile': 'shell',
  '.bashlogout': 'shell',
  '.zshrc': 'shell',
  '.profile': 'shell',
  '.gitignore': 'plaintext',
  '.env': 'properties',
  'properties.ini': 'ini',
};

/// Extensions whose content is prose rather than code. These stay plain even
/// when the highlighter could guess a grammar for them - colouring a README
/// because something in it looked like a Python comment is worse than leaving
/// it alone.
const Set<String> _proseExtensions = {
  'txt', 'md', 'markdown', 'rst', 'adoc', 'log', 'csv', 'tsv', 'text',
};

/// True when [path] is a document rather than something to colour.
bool isProsePath(String path) {
  final name = _baseName(path);
  if (name == 'readme' || name == 'changelog' || name == 'license') return true;
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return false;
  return _proseExtensions.contains(name.substring(dot + 1));
}

String _baseName(String path) =>
    path.split(RegExp(r'[\\/]')).last.toLowerCase();

/// The registered language name to highlight [path] with, or null when there is
/// no grammar for it (markdown, plain text, binary, …) and the caller should
/// render it as plain monospace instead.
String? languageForPath(String path) {
  final name = _baseName(path);

  final byName = _languageByFileName[name];
  if (byName != null) return byName;

  // `Dockerfile.dev`, `Makefile.am`, `.dockerignore` etc.
  for (final special in _languageByFileName.keys) {
    if (name == special || name.startsWith('$special.')) {
      return _languageByFileName[special];
    }
  }

  final dot = name.lastIndexOf('.');
  if (dot <= 0) return null;
  return _languageByExtension[name.substring(dot + 1)];
}

/// Human-readable name for the detected language, for the file viewer header.
const Map<String, String> languageDisplayNames = {
  'c++': 'C/C++',
  'csharp': 'C#',
  'css': 'CSS',
  'javascript': 'JavaScript',
  'plaintext': 'Plain text',
  'properties': 'Properties',
  'typescript': 'TypeScript',
  'xml': 'XML/HTML',
};

String languageDisplayName(String language) =>
    languageDisplayNames[language] ??
    (language.isEmpty ? 'Plain text' : language[0].toUpperCase() + language.substring(1));

/// Split a rendered span tree into one list of spans per line.
///
/// The highlighter produces a single tree for the whole file, which is what
/// makes a multi-line string or a block comment keep its colouring across line
/// breaks; a line-number gutter needs the same content cut up per line. The
/// style a token gets from its ancestors is resolved into each emitted span, so
/// a line rendered on its own looks exactly like it did inside the whole-file
/// tree.
List<List<TextSpan>> splitSpansByLine(List<TextSpan> spans) {
  final lines = <List<TextSpan>>[<TextSpan>[]];

  void walk(TextSpan span, TextStyle? inherited) {
    final effective =
        inherited == null ? span.style : inherited.merge(span.style);
    final text = span.text;
    if (text != null) {
      final parts = text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) lines.add(<TextSpan>[]);
        if (parts[i].isNotEmpty) {
          lines.last.add(TextSpan(text: parts[i], style: effective));
        }
      }
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) walk(child, effective);
    }
  }

  for (final s in spans) {
    walk(s, null);
  }
  return lines;
}

/// Plain text cut into lines in the shape [splitSpansByLine] returns, so the
/// viewer renders a coloured file and a plain one through the same code.
List<List<TextSpan>> plainLines(String source, TextStyle style) => [
    for (final line in source.split('\n'))
      line.isEmpty ? <TextSpan>[] : [TextSpan(text: line, style: style)],
  ];

/// The colours the highlight palette expects to be painted with: its own
/// foreground and its own background.
///
/// A palette is a set of colours for one surface, not colours for any surface.
/// The token colours above are chosen against `root.backgroundColor`; show them
/// on some other background - the app's own, a dialog's - and they are the
/// wrong colours for it, which is what "the colouring is wrong, and it does not
/// follow dark mode" looks like. Anything that renders highlighted text takes
/// both halves from here instead of picking its own background.
({Color foreground, Color background}) codePalette(bool isDark) {
  final theme = isDark ? _darkTheme : _lightTheme;
  return (
    foreground: theme['root']?.color ??
        (isDark ? const Color(0xFFABB2BF) : const Color(0xFF383A42)),
    background: theme['root']?.backgroundColor ??
        (isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA)),
  );
}

/// A block of highlighted code. Same visual result as `HighlightView`, but the
/// parse happens once and the theme/font defaults are the app's own.
class HighlightedCode extends StatelessWidget {
  const HighlightedCode(
    this.source, {
    super.key,
    this.language,
    required this.isDark,
    this.textStyle,
    this.padding = const EdgeInsets.all(8),
    this.background,
    this.borderRadius,
  });

  final String source;
  final String? language;
  final bool isDark;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final palette = codePalette(isDark);
    final base = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 13,
      color: palette.foreground,
    ).merge(textStyle);

    return Container(
      decoration: BoxDecoration(
        color: background ?? palette.background,
        borderRadius: borderRadius ?? BorderRadius.circular(6),
      ),
      padding: padding,
      child: RichText(
        text: TextSpan(style: base, children: highlightedSpans(
          source,
          language: language,
          isDark: isDark,
        )),
        textDirection: TextDirection.ltr,
      ),
    );
  }
}
