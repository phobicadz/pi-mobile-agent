import 'package:flutter/material.dart';

import 'chat_palette.dart' show legibleOn;

/// The Dracula palette, and the Material 3 scheme built from it.
///
/// The other schemes the app offers are *seeds*: pick a hue, let the tonal
/// palette generate the rest, and the contrast pairs come with it. Dracula is
/// not a seed - it is a palette with a point of view. Its background, its
/// comment grey and its pink are the thing people mean when they ask for it, and
/// a generated scheme seeded on Dracula purple does not produce them: Material's
/// neutral scale is not Dracula's near-black-violet surfaces, and its tertiary
/// hue rotation is not Dracula's pink.
///
/// So the roles that carry the palette's identity are authored here - the
/// surfaces, the muted grey, the pink accent, the red - and the roles that are
/// only ever tonal steps of a hue (the purple family and its containers) are
/// left to the generator, seeded on Dracula's own purple. That split is
/// deliberate: hand-picking a `primaryContainer` is where a hand-tuned palette
/// loses the contrast guarantee the generator gives for free.
///
/// The light theme is a separate question, and the honest answer is that there is
/// no light Dracula - it is a dark theme. In light mode this scheme is therefore
/// its purple on a light surface, which is what `AppColorScheme.schemeFor` says
/// to the picker as well as to the code.
class Dracula {
  Dracula._();

  /// The palette as Dracula's own editor themes name it.
  static const background = Color(0xFF282A36);
  static const currentLine = Color(0xFF44475A);
  static const foreground = Color(0xFFF8F8F2);
  static const comment = Color(0xFF6272A4);
  static const cyan = Color(0xFF8BE9FD);
  static const green = Color(0xFF50FA7B);
  static const orange = Color(0xFFFFB86C);
  static const pink = Color(0xFFFF79C6);
  static const purple = Color(0xFFBD93F9);
  static const red = Color(0xFFFF5555);
  static const yellow = Color(0xFFF1FA8C);

  /// The surfaces the app paints with, in Dracula's own steps.
  ///
  /// `background` is the page, `currentLine` is the raised one - which is exactly
  /// what a tool-call card inside a reply needs, so it is used for that rather
  /// than invented for it. The step between them is what a bubble sits on.
  static const surfaceLow = Color(0xFF21222C);
  static const surfaceHigh = Color(0xFF343746);
  static const surfaceHighest = currentLine;

  /// Dracula's muted grey, lightened for use as UI text.
  ///
  /// `comment` is the colour a code editor uses for a comment on its own canvas,
  /// where it is meant to recede. On Dracula's background it is about 3.2:1 -
  /// right for a comment, under what body-adjacent UI text should be. This is
  /// the same hue pushed to ~4.7:1, which is what `onSurfaceVariant` is for.
  static const commentOnDark = Color(0xFF8A93C4);

  /// The scheme this app builds its dark theme from when Dracula is chosen.
  static ColorScheme darkScheme() {
    // Seeded on Dracula's purple so the primary family - and the containers and
    // fixed variants that go with it - are Dracula's hue with Material's tonal
    // spacing, rather than a guess at it.
    final base =
        ColorScheme.fromSeed(seedColor: purple, brightness: Brightness.dark);

    return base.copyWith(
      // The palette's surfaces, top to bottom.
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: commentOnDark,
      surfaceContainerLowest: Color(0xFF1B1C24),
      surfaceContainerLow: surfaceLow,
      surfaceContainer: background,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHighest,

      // `surfaceVariant`, `background` and `onBackground` are the pre-3.22 names
      // for three of the above; setting them would only be repeating it.

      // The accent a reply is drawn in. Left to the generator this would be a
      // hue rotation away from the purple; in Dracula that rotation is not a
      // colour that exists.
      tertiary: pink,
      onTertiary: background,
      tertiaryFixed: pink,
      onTertiaryFixed: background,
      tertiaryFixedDim: Color(0xFFD06AAB),
      onTertiaryFixedVariant: Color(0xFF4A2239),
      tertiaryContainer: Color(0xFF5C2B45),
      onTertiaryContainer: foreground,

      // Dracula's red, on surfaces tinted with it.
      //
      // Its red raised on the bubble it is read on. `#FF5555` on `#343746` is
      // 3.75:1, which is a colour a reader has to squint at - and an error is
      // the last thing in the app that should be allowed to be hard to read.
      // `legibleOn` moves lightness only, so this is still Dracula's red.
      error: legibleOn(red, surfaceHigh),
      onError: background,
      errorContainer: Color(0xFF5C2B2B),
      onErrorContainer: foreground,

      // Hairlines and disabled chrome, in the palette's own greys.
      outline: comment,
      outlineVariant: currentLine,

      // Kept in the palette's family rather than Material's default blue-ish
      // secondary, which would show up in chips and selection chrome.
      secondary: cyan,
      onSecondary: background,
      secondaryContainer: Color(0xFF2C4150),
      onSecondaryContainer: foreground,
    );
  }
}
