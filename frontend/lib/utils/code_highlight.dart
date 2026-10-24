import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/highlight_core.dart' show Highlight, Node;
import 'package:highlight/languages/bash.dart' show bash;
import 'package:highlight/languages/cpp.dart' show cpp;
import 'package:highlight/languages/cs.dart' show cs;
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
import 'package:highlight/languages/xml.dart' show xml;
import 'package:highlight/languages/yaml.dart' show yaml;

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
final Highlight _highlighter = Highlight()
  ..registerLanguages({
    'bash': bash,
    'shell': shell,
    'c++': cpp,
    'csharp': cs,
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
    final theme = isDark ? _darkTheme : _lightTheme;
    final base = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 13,
      color: theme['root']?.color ?? (isDark ? const Color(0xFFABB2BF) : const Color(0xFF383A42)),
    ).merge(textStyle);

    return Container(
      decoration: BoxDecoration(
        color: background ??
            theme['root']?.backgroundColor ??
            (isDark ? const Color(0xFF282C34) : const Color(0xFFFAFAFA)),
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
