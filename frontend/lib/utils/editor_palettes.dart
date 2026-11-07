import 'package:flutter/material.dart';

import 'chat_palette.dart' show contrastOn, legibleOn;

/// A colour theme as an editor names it: the colours that theme publishes, and
/// nothing more.
///
/// The app's own schemes (`AppColorScheme.blue`, `green`, …) are *seeds*: pick a
/// hue, let Material's tonal palette generate the surfaces and the contrast
/// pairs. That is the right tool for "make it green". It is the wrong tool for
/// "make it Solarized", because a palette like that is not a hue - it is a set
/// of surfaces and a handful of accents people recognise by name, and the
/// generator will not produce them from a seed.
///
/// So an `EditorPalette` carries only what each theme actually publishes:
///
/// * its background, its body text, its comment grey,
/// * the accents the roles here need - your side of the chat, Pi's side, errors,
/// * and its own "current line" / selection step, where it publishes one.
///
/// The *surface scale* is derived, by one rule, for every palette: a step away
/// from the background toward the page, and one step toward the text. Themes
/// publish a background and a highlight colour, not a five-step Material scale,
/// and inventing hexes to fill it out then calling them the theme's colours
/// would be a claim this file could not keep. Deriving it means every palette
/// behaves the same way in the app - a bubble, a card and a page that relate to
/// each other the same way whatever the colours are - and the only colours
/// claimed as "the theme's" are the ones the theme names.
///
/// The accents keep their hue. Where one is too dim for the surface it is drawn
/// on it is nudged in *lightness* only (`legibleOn`), which is the same fix
/// `Dracula.commentOnDark` records by hand for one palette, applied to all of
/// them.
class EditorPalette {
  const EditorPalette({
    required this.name,
    required this.background,
    required this.foreground,
    required this.comment,
    required this.primary,
    required this.tertiary,
    required this.error,
    this.raised,
  });

  /// The name the theme itself uses, for a test failure or a log line.
  final String name;

  /// The page. Everything else in the app is a step from here.
  final Color background;

  /// Body text, as the theme's own syntax palette names it.
  final Color foreground;

  /// The theme's receding grey - a comment colour, which is designed to be read
  /// on the theme's own canvas and is usually too dim for UI text. Raised only
  /// as far as the surface it lands on needs.
  final Color comment;

  /// Your side of the chat: your bubbles, links, the active controls.
  final Color primary;

  /// Pi's side: the accent on a reply. A different hue from `primary` is the
  /// whole distinction, so it is authored here rather than derived.
  final Color tertiary;

  final Color error;

  /// The theme's own one-step-raised surface (current line, selection). Where a
  /// theme does not publish one, it is derived instead - see the class comment.
  final Color? raised;

  /// The Material 3 scheme this app builds its chat from for this palette.
  ///
  /// The tonal *spacing* still comes from the generator, seeded on the palette's
  /// own accent: the containers and their `on*` pairs are the part a generator
  /// gets right for free, and hand-picking them is where a hand-tuned palette
  /// loses that guarantee. What is authored is the parts that carry the
  /// palette's identity - the surfaces, the greys, the accents.
  ColorScheme schemeFor(Brightness brightness) =>
      _scheme(light: brightness == Brightness.light);

  ColorScheme _scheme({required bool light}) {
    final brightness = light ? Brightness.light : Brightness.dark;
    final base = ColorScheme.fromSeed(seedColor: primary, brightness: brightness);

    Color step(Color from, Color to, double t) => Color.lerp(from, to, t)!;

    // One step toward the text. In a dark theme that is a lighter surface, in a
    // light theme a darker one - which is the same thing: the surface an editor
    // raises under the cursor, or highlights a selection with.
    final raised = this.raised ?? step(background, foreground, 0.08);

    // And the other way: toward the page, for the surfaces a bubble sits *on*.
    final page = light ? Colors.white : Colors.black;
    final bubble = step(background, raised, 0.6);
    final card = raised;

    // The accents, raised only as far as the surface they are read on. A hue is
    // untouched by a lerp toward black or white, so this changes how light a
    // colour is and never which colour it is.
    final accent = legibleOn(primary, background);
    final replyAccent = legibleOn(tertiary, bubble);
    final errorAccent = legibleOn(error, bubble);
    final muted = legibleOn(comment, card);

    // A container is the accent laid *over* the surface it belongs to, so it
    // stays a surface of this palette rather than a swatch of the accent.
    Color container(Color accentColor) => Color.alphaBlend(
        accentColor.withValues(alpha: light ? 0.16 : 0.34), bubble);

    final userBubble = container(accent);
    final replyContainer = container(replyAccent);
    final errorContainer = container(errorAccent);

    // Whichever of black or white reads better on a fill is the text on it.
    Color on(Color fill) =>
        contrastOn(Colors.black, fill) >= contrastOn(Colors.white, fill)
            ? Colors.black
            : Colors.white;

    return base.copyWith(
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: muted,
      surfaceContainerLowest: step(background, page, light ? 0.6 : 0.22),
      surfaceContainerLow: step(background, page, light ? 0.3 : 0.08),
      surfaceContainer: background,
      surfaceContainerHigh: bubble,
      surfaceContainerHighest: card,

      primary: accent,
      onPrimary: on(accent),
      primaryContainer: userBubble,
      onPrimaryContainer: legibleOn(foreground, userBubble),

      tertiary: replyAccent,
      onTertiary: on(replyAccent),
      tertiaryContainer: replyContainer,
      onTertiaryContainer: legibleOn(foreground, replyContainer),

      error: errorAccent,
      onError: on(errorAccent),
      errorContainer: errorContainer,
      onErrorContainer: legibleOn(foreground, errorContainer),

      outline: muted,
      outlineVariant: step(raised, foreground, light ? 0.28 : 0.22),
    );
  }

  /// -----------------------------------------------------------------------
  /// The palettes. Every value below is one the theme in question names; where
  /// a step is derived rather than published, `raised` is left out and the
  /// class comment says so.
  /// -----------------------------------------------------------------------

  /// Atom One Dark / Atom One Light - the most-installed "theme" in the VS Code
  /// marketplace, and the palette this app's code blocks are already coloured
  /// with: these background, text, comment and accent values are the ones in
  /// `flutter_highlight`'s own `atom-one-dark` / `atom-one-light` theme files.
  static const atomOneDark = EditorPalette(
    name: 'Atom One Dark',
    background: Color(0xFF282C34),
    foreground: Color(0xFFABB2BF),
    comment: Color(0xFF5C6370),
    primary: Color(0xFF61AEEE),
    tertiary: Color(0xFFC678DD),
    error: Color(0xFFE06C75),
  );

  static const atomOneLight = EditorPalette(
    name: 'Atom One Light',
    background: Color(0xFFFAFAFA),
    foreground: Color(0xFF383A42),
    comment: Color(0xFFA0A1A7),
    primary: Color(0xFF4078F2),
    tertiary: Color(0xFFA626A4),
    error: Color(0xFFE45649),
  );

  /// Solarized - designed as a *pair*, with the same eight accents and two
  /// surfaces flipped so the accents keep their contrast on either background.
  /// The base03/base02 and base3/base2 surface steps are the palette's own.
  static const solarizedDark = EditorPalette(
    name: 'Solarized Dark',
    background: Color(0xFF002B36),
    raised: Color(0xFF073642),
    foreground: Color(0xFF93A1A1),
    comment: Color(0xFF586E75),
    primary: Color(0xFF268BD2),
    tertiary: Color(0xFFD33682),
    error: Color(0xFFDC322F),
  );

  static const solarizedLight = EditorPalette(
    name: 'Solarized Light',
    background: Color(0xFFFDF6E3),
    raised: Color(0xFFEEE8D5),
    foreground: Color(0xFF073642),
    comment: Color(0xFF93A1A1),
    primary: Color(0xFF268BD2),
    tertiary: Color(0xFFD33682),
    error: Color(0xFFDC322F),
  );

  /// GitHub Dark / GitHub Light - GitHub's own interface palette (its Primer
  /// canvas, text and "fg" accent colours), which is also what the GitHub
  /// theme for VS Code paints an editor with.
  static const githubDark = EditorPalette(
    name: 'GitHub Dark',
    background: Color(0xFF0D1117),
    raised: Color(0xFF161B22),
    foreground: Color(0xFFC9D1D9),
    comment: Color(0xFF8B949E),
    primary: Color(0xFF58A6FF),
    tertiary: Color(0xFFBC8CFF),
    error: Color(0xFFF85149),
  );

  static const githubLight = EditorPalette(
    name: 'GitHub Light',
    background: Color(0xFFFFFFFF),
    raised: Color(0xFFF6F8FA),
    foreground: Color(0xFF1F2328),
    comment: Color(0xFF656C76),
    primary: Color(0xFF0969DA),
    tertiary: Color(0xFF8250DF),
    error: Color(0xFFCF222E),
  );

  /// Nord - the arctic palette, whose eight "polar night" and "snow storm"
  /// greys are the theme's whole point. Its low-saturation accents are the
  /// quietest palette here, and stay that way: nothing here needs raising.
  static const nord = EditorPalette(
    name: 'Nord',
    background: Color(0xFF2E3440),
    raised: Color(0xFF434C5E),
    foreground: Color(0xFFECEFF4),
    comment: Color(0xFF4C566A),
    primary: Color(0xFF81A1C1),
    tertiary: Color(0xFFB48EAD),
    error: Color(0xFFBF616A),
  );

  /// Catppuccin Mocha - the warm dark palette currently everywhere, named in
  /// layers (`base`, `mantle`, `surface0`) rather than shades.
  static const catppuccinMocha = EditorPalette(
    name: 'Catppuccin Mocha',
    background: Color(0xFF1E1E2E),
    raised: Color(0xFF313244),
    foreground: Color(0xFFCDD6F4),
    comment: Color(0xFF7F849C),
    primary: Color(0xFF89B4FA),
    tertiary: Color(0xFFCBA6F7),
    error: Color(0xFFF38BA8),
  );

  /// Tokyo Night - the night-city palette. Its blue is the theme's identity, so
  /// that stays the accent of *your* messages; the other side of the chat takes
  /// the theme's own orange, which is unmistakable against the navy rather than
  /// a second blue-violet 40° away from it.
  static const tokyoNight = EditorPalette(
    name: 'Tokyo Night',
    background: Color(0xFF1A1B26),
    raised: Color(0xFF292E42),
    foreground: Color(0xFFC0CAF5),
    comment: Color(0xFF565F89),
    primary: Color(0xFF7AA2F7),
    tertiary: Color(0xFFFF9E64),
    error: Color(0xFFF7768E),
  );

  /// Monokai - the one every editor has shipped at some point, VS Code's default
  /// dark theme included. Its pink is its identity, so that is what a *failure*
  /// is drawn in here, and the cyan and purple do the two chat roles.
  static const monokai = EditorPalette(
    name: 'Monokai',
    background: Color(0xFF272822),
    raised: Color(0xFF49483E),
    foreground: Color(0xFFF8F8F2),
    comment: Color(0xFF75715E),
    primary: Color(0xFF66D9EF),
    tertiary: Color(0xFFAE81FF),
    error: Color(0xFFF92672),
  );
}
