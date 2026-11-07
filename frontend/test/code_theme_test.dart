import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/utils/chat_palette.dart';
import 'package:pi_mobile_agent/utils/code_highlight.dart';
import 'package:pi_mobile_agent/utils/code_theme.dart';
import 'package:pi_mobile_agent/utils/editor_palettes.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';

/// Picking a theme is one decision, and it has to reach the code too.
///
/// The chat follows the scheme; these are the tests that the *code* does. They
/// are separate from `editor_palettes_test.dart`, which is about surfaces and
/// accents, because a syntax palette is a different set of colours with different
/// rules: its colours are roles in a program, and they are only correct on the
/// surface they were measured against.
const _authored = <AppColorScheme, EditorPalette>{
  AppColorScheme.atomOne: EditorPalette.atomOneDark,
  AppColorScheme.solarized: EditorPalette.solarizedDark,
  AppColorScheme.github: EditorPalette.githubDark,
  AppColorScheme.nord: EditorPalette.nord,
  AppColorScheme.catppuccin: EditorPalette.catppuccinMocha,
  AppColorScheme.tokyoNight: EditorPalette.tokyoNight,
  AppColorScheme.monokai: EditorPalette.monokai,
};

/// The roles a code theme is judged by: the ones a reader notices.
const _roles = ['keyword', 'string', 'number', 'title', 'variable', 'type', 'tag'];

/// The keys a grammar emits for each role.
///
/// The app's own maps carry every one under its own name; the stock Atom One map
/// uses the older names for the same thing - what this file calls a tag it calls
/// `name`, `section` and `deletion`. A role is looked up by any name it has,
/// because the question is whether the *reader* sees a colour there.
const _roleKeys = {
  'keyword': ['keyword'],
  'string': ['string'],
  'number': ['number'],
  'title': ['title'],
  'variable': ['variable'],
  'type': ['type'],
  'tag': ['tag', 'name', 'section', 'deletion'],
};

Color? _token(Map<String, TextStyle> map, String role) {
  for (final key in _roleKeys[role]!) {
    final style = map[key];
    if (style?.color != null) return style!.color;
  }
  return null;
}

double _hue(Color color) => HSLColor.fromColor(color).hue;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// A theme built the way `main.dart` builds it - the code theme travels on the
/// ThemeData, because that is the only thing every widget drawing code already
/// has in common.
ThemeData themeFor(AppColorScheme scheme, Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: scheme.schemeFor(brightness),
      brightness: brightness,
      extensions: [CodeTheme.following(scheme, brightness)],
    );

void main() {
  test('a seeded scheme gets the app’s default code theme', () {
    // A Material seed is not an editor theme. There is no syntax palette to
    // follow, and inventing one from a seed colour would be the app making up a
    // theme and naming it after the scheme that only asked for a hue.
    for (final scheme in [
      AppColorScheme.blue,
      AppColorScheme.green,
      AppColorScheme.red,
    ]) {
      for (final brightness in Brightness.values) {
        final theme = themeFor(scheme, brightness);
        final code = CodeTheme.of(theme);
        expect(code.ownsAppSurfaces, isFalse,
            reason: '${scheme.name} / $brightness');
        // On its own background the stock theme is used exactly as published -
        // which is what the file viewer does, and what "the default is unchanged"
        // has to mean before anything else.
        expect(code.mapFor(code.fixedBackground),
            brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme,
            reason: '${scheme.name} / $brightness is the theme the app was '
                'built with, unchanged');
        // On one of the app's surfaces it is the same theme's hues, raised enough
        // to read there. A dark syntax palette painted on a light app without any
        // adjustment is how a string in a reply used to read as 3.2:1 grey.
        final surface = CodeTheme.codeSurface(theme.colorScheme);
        final map = code.mapFor(surface);
        expect(map, isNot(atomOneDarkTheme));
        for (final role in _roles) {
          expect(_contrast(_token(map, role)!, surface),
              greaterThanOrEqualTo(4.0),
              reason: '${scheme.name} / $brightness $role on the app’s own '
                  'code surface');
        }
      }
    }
  });

  test('an editor theme colours code with its own syntax palette', () {
    for (final entry in _authored.entries) {
      final scheme = entry.key;
      final syntax = entry.value.syntax!;
      final theme = themeFor(scheme, Brightness.dark);
      final code = CodeTheme.of(theme);
      final surface = CodeTheme.codeSurface(theme.colorScheme);
      final map = code.mapFor(surface);
      final what = '${entry.value.name} / dark';

      expect(code.ownsAppSurfaces, isTrue, reason: what);

      for (final role in _roles) {
        final published = switch (role) {
          'keyword' => syntax.keyword,
          'string' => syntax.string,
          'number' => syntax.number,
          'title' => syntax.title,
          'variable' => syntax.variable,
          'type' => syntax.type,
          _ => syntax.tag,
        };
        final drawn = _token(map, role)!;
        // The hue is the theme. The lightness may move, because a token colour
        // has to be readable on this surface - which is the app's own surface,
        // not the one the theme was published on.
        expect((_hue(drawn) - _hue(published)).abs(), lessThan(1.0),
            reason: '$what $role: the token kept its hue, or it is a different '
                'theme with this theme’s name');
        expect(_contrast(drawn, surface), greaterThanOrEqualTo(4.0),
            reason: '$what $role: a token colour nobody can read is not a theme '
                'colour, it is a smudge');
      }
    }
  });

  test('two editor themes do not end up colouring code the same way', () {
    // The point of offering themes is that they look different. If every syntax
    // palette collapsed onto the same eight hues, the picker would be decoration.
    final solarized = CodeTheme.of(themeFor(AppColorScheme.solarized, Brightness.dark));
    final monokai = CodeTheme.of(themeFor(AppColorScheme.monokai, Brightness.dark));
    final a = solarized.mapFor(CodeTheme.codeSurface(
        themeFor(AppColorScheme.solarized, Brightness.dark).colorScheme));
    final b = monokai.mapFor(CodeTheme.codeSurface(
        themeFor(AppColorScheme.monokai, Brightness.dark).colorScheme));

    var different = 0;
    for (final role in _roles) {
      if ((_hue(_token(a, role)!) - _hue(_token(b, role)!)).abs() > 10) different++;
    }
    expect(different, greaterThanOrEqualTo(3),
        reason: 'Solarized and Monokai are the two most different themes here; '
            'if their code looked alike, the choice would not reach the code');
  });

  test('a dark-only theme keeps a light code theme in light mode', () {
    // Picking Nord in light mode gives you a light app generated from Nord’s
    // hue - and a light app whose code is coloured by a *dark* syntax palette is
    // dark tokens on a light surface, which is the failure mode the file viewer
    // documents. There is no light Nord to follow, and the app says so rather
    // than inventing one.
    for (final scheme in AppColorScheme.values.where((s) => s.isDarkOnly)) {
      final code = CodeTheme.of(themeFor(scheme, Brightness.light));
      expect(code.ownsAppSurfaces, isFalse,
          reason: '${scheme.displayName} has no light half to take syntax from');
      expect(code.id, startsWith('atom-one'), reason: scheme.name);
    }
  });

  test('the code theme is legible on the surface the chat paints code on', () {
    // `ChatPalette.codeBackground` is the surface; `mapFor` is measured against
    // whatever surface it is handed. This is the two meeting, which is where a
    // mismatch would live.
    for (final scheme in AppColorScheme.values) {
      for (final brightness in Brightness.values) {
        final theme = themeFor(scheme, brightness);
        final chat = ChatPalette.from(theme);
        final map = CodeTheme.of(theme).mapFor(chat.codeBackground);
        final what = '${scheme.displayName} / $brightness';

        // The tokens are the map's business; the text between them belongs to
        // the surface it is drawn on, and `HighlightedCode` paints that text
        // from `ChatPalette.codeForeground` (which is what the tool-card tests
        // check). What has to agree here is the *legibility* of both.
        for (final role in _roles) {
          final colour = _token(map, role);
          expect(colour, isNotNull, reason: '$what: $role has no colour');
          expect(_contrast(colour!, chat.codeBackground),
              greaterThanOrEqualTo(4.0),
              reason: '$what $role on a code block');
        }
        for (final surface in [chat.addedBlock, chat.removedBlock]) {
          final tinted = CodeTheme.of(theme).mapFor(surface);
          expect(_contrast(_token(tinted, 'string')!, surface),
              greaterThanOrEqualTo(4.0),
              reason: '$what: a diff half is tinted, and a token colour is only '
                  'legible against the block it is actually painted on');
        }
      }
    }
  });

  test('a rendered block cannot be handed back from another theme’s cache', () {
    // Span trees are cached by source, because parsing a 400-line file on every
    // frame is its own bug. A colour is baked into a span, so the key has to
    // carry which theme baked it.
    const source = 'final count = 42;';
    final solarized = CodeTheme.of(themeFor(AppColorScheme.solarized, Brightness.dark));
    final monokai = CodeTheme.of(themeFor(AppColorScheme.monokai, Brightness.dark));

    final a = highlightedSpans(source,
        language: 'dart',
        isDark: true,
        theme: solarized.mapFor(CodeTheme.codeSurface(
            themeFor(AppColorScheme.solarized, Brightness.dark).colorScheme)),
        themeId: solarized.id);
    final b = highlightedSpans(source,
        language: 'dart',
        isDark: true,
        theme: monokai.mapFor(
            CodeTheme.codeSurface(themeFor(AppColorScheme.monokai, Brightness.dark).colorScheme)),
        themeId: monokai.id);

    List<Color> colours(List<TextSpan> spans) => [
          for (final s in spans) ...[if (s.style?.color != null) s.style!.color!],
        ];
    expect(colours(a), isNotEmpty, reason: 'the grammar found tokens to colour');
    expect(colours(a), isNot(equals(colours(b))),
        reason: 'the same source under two themes came back with the same '
            'colours, which is a cache key that does not know about themes');
  });

  test('the code theme is part of what a cached bubble has to be told about',
      () {
    // A cached bubble is a subtree with literal colours in it. The spans inside
    // its code blocks are cached separately, and `ChatPalette` is what both are
    // built from - so it has to remember which code theme it was built for.
    for (final scheme in AppColorScheme.values) {
      final chat = ChatPalette.from(themeFor(scheme, Brightness.dark));
      expect(chat.codeThemeId, isNotEmpty, reason: scheme.name);
    }
    final blue = ChatPalette.from(themeFor(AppColorScheme.blue, Brightness.dark));
    final solarized =
        ChatPalette.from(themeFor(AppColorScheme.solarized, Brightness.dark));
    expect(blue.codeThemeId, isNot(solarized.codeThemeId));
    expect(blue.cacheKey, isNot(solarized.cacheKey));
  });

  testWidgets('a fenced block in a reply is coloured with the theme that was '
      'picked, end to end', (tester) async {
    // The tests above prove the map is right. This one proves the map is *used*:
    // that a string in a reply a phone is actually showing comes out in Solarized
    // green and not in the app default’s green, which is the question this
    // feature exists to answer.
    final theme = themeFor(AppColorScheme.solarized, Brightness.dark);
    final syntax = EditorPalette.solarizedDark.syntax!;
    final message = PiMessage(
      id: 'c1',
      role: 'assistant',
      content: '```dart\nconst label = "solarized";\n```',
      timestamp: DateTime(2026),
    );

    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(body: ListView(children: [ChatBubble(message: message)])),
    ));
    await tester.pump(const Duration(milliseconds: 120));

    final text = tester.widget<Text>(find
        .descendant(
            of: find.byType(HighlightedCode), matching: find.byType(Text))
        .first);
    final colours = <Color>[];
    void walk(TextSpan span) {
      final colour = span.style?.color;
      if (colour != null) colours.add(colour);
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (child is TextSpan) walk(child);
      }
    }
    walk(text.textSpan as TextSpan);

    expect(colours.length, greaterThan(1),
        reason: 'the grammar found something to colour, or there is nothing to '
            'check');
    final stringHue = _hue(syntax.string);
    expect(
        colours.any((c) => (_hue(c) - stringHue).abs() < 2),
        isTrue,
        reason: 'no string in the block is Solarized’s green');
    expect(colours, isNot(contains(const Color(0xFF98C379))),
        reason: 'Atom One’s green is what the app default paints a string with; '
            'finding it here would mean the choice never reached the code');
  });

  test('a theme without a code theme on it still draws code', () {
    // Every widget that draws code reads the theme it is given. A widget tree
    // built without the extension - a test, a dialog, a preview - must get the
    // app’s default rather than nothing.
    final bare = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue, brightness: Brightness.dark),
      brightness: Brightness.dark,
    );
    final code = CodeTheme.of(bare);
    expect(code.id, startsWith('atom-one'));
    expect(code.ownsAppSurfaces, isFalse);
    expect(code.mapFor(code.fixedBackground), atomOneDarkTheme);
    // On the app’s own surface, the text of a block is the app’s text colour -
    // the surface owns the colour, not the theme borrowed for it.
    expect(
        code.foregroundFor(CodeTheme.codeSurface(bare.colorScheme),
            appText: bare.colorScheme.onSurface),
        bare.colorScheme.onSurface);
  });
}
