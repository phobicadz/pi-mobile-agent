import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';

import '../providers/appearance_controller.dart';
import 'chat_palette.dart' show legibleOn;
import 'dracula_scheme.dart';
import 'editor_palettes.dart';

/// Which syntax palette this app colours code with, carried on the theme.
///
/// It lives on `ThemeData` rather than being passed down, because everything
/// that draws code - a fenced block, a tool call's command, a diff half, the
/// file viewer - is deep in a widget tree that would otherwise have to be handed
/// it, and a code theme threaded through eight constructors is a code theme that
/// gets forgotten in the ninth.
///
/// Two kinds:
///
/// * **follows the palette** (`ownsAppSurfaces`): the syntax colours come from
///   the same theme the chat is painted from, so picking Solarized colours
///   strings in Solarized green. Its tokens belong to *this app's* surfaces, so
///   the block they sit on is the app's own surface too.
/// * **the app's default** (Atom One): what a scheme with no syntax palette of
///   its own gets - a Material seed is not an editor theme. Its tokens were
///   chosen against its own background, so a block using it takes that
///   background - the rule `file_viewer.dart` records.
class CodeTheme extends ThemeExtension<CodeTheme> {
  const CodeTheme._({
    required this.id,
    required this.displayName,
    required this.palette,
    required this.ownsAppSurfaces,
    required this.fixedMap,
    required this.fixedForeground,
    required this.fixedBackground,
  });

  /// Identifies the theme in a cache key. A rendered span tree has its token
  /// colours baked in, so a cache keyed on source and brightness alone would
  /// hand back the old colours after a scheme change - the same bug the bubble
  /// cache had, one layer down.
  final String id;
  final String displayName;

  /// Whether this theme's tokens belong to the app's own surfaces.
  ///
  /// True for a theme derived from the app's chosen palette, false for the app's
  /// default code theme - which is the one thing that still has a background of
  /// its own worth painting on, and the reason the file viewer asks.
  final bool ownsAppSurfaces;

  /// The surface and text colour the theme is at home on: its own background, or
  /// - for a derived theme - the palette's.
  final Color fixedForeground;
  final Color fixedBackground;

  /// The default theme's stock map, used verbatim when the code is painted on
  /// `fixedBackground`. Null for a derived theme, which has no stock version.
  final Map<String, TextStyle>? fixedMap;

  /// The roles to colour from. Never null: either the chosen palette or the
  /// default theme's own, whose syntax this app already publishes.
  final EditorPalette palette;

  /// The surface code is painted on, from the colour scheme.
  ///
  /// A near-neutral step off the page, and deliberately *not* a chromatic
  /// container: a syntax palette's token colours were chosen against greys, and
  /// a `surfaceContainerHighest`-style token tinted with the scheme's own hue
  /// makes every keyword in a block look like a button.
  static Color codeSurface(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
          ? scheme.surfaceContainer
          : scheme.surfaceContainerLowest;

  /// The theme a widget is actually being drawn with.
  static CodeTheme of(ThemeData theme) =>
      theme.extension<CodeTheme>() ?? atomOne(theme.brightness);

  /// The app's default: Atom One, the theme the app was built with.
  ///
  /// Its published syntax is the same theme's (`EditorPalette.atomOneDark` is
  /// read off the stock map), so a block painted on one of the app's own surfaces
  /// gets the same hues raised enough to be read there - and a block painted on
  /// Atom One's own background gets Atom One, unchanged.
  static CodeTheme atomOne(Brightness brightness) {
    final home = brightness == Brightness.dark
        ? EditorPalette.atomOneDark
        : EditorPalette.atomOneLight;
    return CodeTheme._(
      id: brightness == Brightness.dark ? 'atom-one-dark' : 'atom-one-light',
      displayName: home.name,
      palette: home,
      ownsAppSurfaces: false,
      fixedMap:
          brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme,
      fixedForeground: home.foreground,
      fixedBackground: home.background,
    );
  }

  /// The theme that follows the app's chosen colour scheme.
  ///
  /// A scheme with no authored palette at this brightness - a Material seed, or
  /// a dark-only editor theme in light mode - gets the app's default, which is
  /// the honest answer: there is no syntax palette to follow.
  static CodeTheme following(AppColorScheme scheme, Brightness brightness) {
    if (scheme == AppColorScheme.dracula && brightness == Brightness.dark) {
      return _derived(_draculaAsEditorPalette, 'dracula', 'Dracula');
    }
    final palette = scheme.authoredAt(brightness);
    if (palette == null) return atomOne(brightness);
    return _derived(palette, palette.name.toLowerCase().replaceAll(' ', '-'),
        palette.name);
  }

  static CodeTheme _derived(EditorPalette palette, String id, String name) =>
      CodeTheme._(
        id: id,
        displayName: name,
        palette: palette,
        ownsAppSurfaces: true,
        fixedMap: null,
        fixedForeground: palette.foreground,
        fixedBackground: palette.background,
      );

  /// The token map for code painted on [codeBackground].
  ///
  /// Derived per surface on purpose: a token colour is only legible *relative to
  /// the block it is drawn on*, and the app paints code on its own surfaces,
  /// which differ per scheme. The one exception is the default theme on its own
  /// background, where the published map is used exactly as published.
  ///
  /// Built once per (theme, surface) and reused.
  Map<String, TextStyle> mapFor(Color codeBackground) {
    final fixed = fixedMap;
    if (fixed != null && codeBackground == fixedBackground) return fixed;

    final key = '$id|${codeBackground.toARGB32()}';
    final cached = _maps[key];
    if (cached != null) return cached;

    final built = palette.syntaxTheme(codeBackground);
    if (_maps.length > 32) _maps.clear();
    _maps[key] = built;
    return built;
  }

  /// The colour un-tokened code text gets on [codeBackground].
  ///
  /// Whichever surface the code is actually on owns that colour. Painted on a
  /// code theme's own background, it is the theme's own foreground - the theme
  /// and its surface are one design, which is the whole reason the file viewer
  /// keeps them together. Painted on the app's surface, it is the app's text:
  /// the parts of a command a grammar leaves alone - a path, a subcommand - are
  /// text, and text in the app is the app's colour. A theme derived from the
  /// app's palette has a foreground of its own that belongs to that surface, so
  /// it is that one. Raised in lightness only, either way.
  Color foregroundFor(Color codeBackground, {required Color appText}) {
    final base = codeBackground == fixedBackground
        ? fixedForeground
        : (ownsAppSurfaces ? palette.foreground : appText);
    return legibleOn(base, codeBackground);
  }

  static final Map<String, Map<String, TextStyle>> _maps = {};

  @override
  ThemeExtension<CodeTheme> copyWith({String? id, String? displayName}) =>
      CodeTheme._(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        palette: palette,
        ownsAppSurfaces: ownsAppSurfaces,
        fixedMap: fixedMap,
        fixedForeground: fixedForeground,
        fixedBackground: fixedBackground,
      );

  /// A theme is swapped, not blended: two syntax palettes interpolated halfway
  /// are a third one nobody chose.
  @override
  ThemeExtension<CodeTheme> lerp(ThemeExtension<CodeTheme>? other, double t) =>
      other is CodeTheme && t >= 0.5 ? other : this;
}

/// Dracula as the app's own file does not hold it: an `EditorPalette`, so its
/// published syntax colours reach the highlighter the same way every other
/// editor theme's do. Its *surfaces* stay in `dracula_scheme.dart`, which is
/// where the app's Dracula scheme is built.
const _draculaAsEditorPalette = EditorPalette(
  name: 'Dracula',
  background: Dracula.background,
  raised: Dracula.surfaceHighest,
  foreground: Dracula.foreground,
  comment: Dracula.comment,
  primary: Dracula.purple,
  tertiary: Dracula.pink,
  error: Dracula.red,
  syntax: EditorSyntax(
    comment: Dracula.comment,
    keyword: Dracula.pink,
    string: Dracula.yellow,
    number: Dracula.purple,
    title: Dracula.green,
    variable: Dracula.orange,
    type: Dracula.cyan,
    tag: Dracula.red,
  ),
);
