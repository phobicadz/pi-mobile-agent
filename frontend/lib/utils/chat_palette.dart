import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'code_theme.dart';

/// The chat's colours, read off whichever colour scheme the app is on.
///
/// The bubbles used to carry their own hex literals. That worked while there was
/// exactly one blue scheme, and broke the moment the app offered others: picking
/// green or purple changed the bar and the buttons and left the chat blue, which
/// reads as the setting having been half applied.
///
/// So every colour here is a Material 3 *token pair* rather than a hand-picked
/// colour. That is not just about following the setting - `primaryContainer`
/// with `onPrimaryContainer`, `onSurface` on a `surfaceContainer*`, `error` on a
/// surface: those are the combinations the tonal palette is generated to be
/// legible on each other, at either brightness, for any seed. The literals were
/// an attempt at the same guarantee for one seed only.
///
/// Two roles, deliberately still two hues: your own messages take the scheme's
/// `primary` family, Pi's replies take `tertiary`, which the palette derives as a
/// rotation away from the seed. A scheme change moves both, and "Pi" and "You"
/// stay distinguishable whatever the seed is.
///
/// Tool *results* keep their green on purpose. It is the one signal in the chat
/// that says "this is output", and a signal that moves with the user's colour
/// preference stops being a signal.
class ChatPalette {
  const ChatPalette({
    required this.isDark,
    required this.assistantBubble,
    required this.userBubble,
    required this.assistantAccent,
    required this.userAccent,
    required this.assistantBody,
    required this.userBody,
    required this.muted,
    required this.toolCard,
    required this.codeBackground,
    required this.codeForeground,
    required this.codeThemeId,
    required this.diffAdded,
    required this.diffRemoved,
    required this.addedBlock,
    required this.removedBlock,
    required this.toolText,
    required this.toolError,
    required this.toolResult,
    required this.link,
    required this.error,
    required this.outline,
    required this.inlineCodeBackground,
  });

  final bool isDark;

  /// Bubble backgrounds. Pi's stays neutral so a wall of replies is calm and the
  /// accent does the distinguishing; yours takes the scheme's hue, which is what
  /// makes the chat visibly *yours* once a scheme is chosen.
  final Color assistantBubble;
  final Color userBubble;

  /// The header icon/label, the tool-call label, the glow around a live reply.
  final Color assistantAccent;
  final Color userAccent;

  /// Body text, paired with its own bubble by construction.
  final Color assistantBody;
  final Color userBody;

  final Color muted;

  /// A tool call's card, raised off the reply it sits in.
  final Color toolCard;

  /// Tool output. Not derived from the scheme - see the class comment.
  final Color toolResult;

  /// The block a piece of code is painted on inside a reply - a fenced block,
  /// a tool call's command, a tool's output - and its un-tokened text.
  ///
  /// In the theme's own surfaces rather than a code theme's background: the
  /// bubble and the tool card around them are already painted from the scheme,
  /// and a block of one-dark grey inside a Dracula card is two palettes in the
  /// same box.
  ///
  /// Recessed *toward the page* at either brightness - which is a different
  /// token per theme, because the surface scale runs the other way in dark. A
  /// block that goes the same direction in both would sit proud of its card at
  /// one brightness and sunk into it at the other.
  ///
  /// The *surface* is the app's, deliberately: it is a near-neutral step off the
  /// page, and a block tinted in the scheme's own hue makes every keyword in it
  /// look like a button. The **token colours** on it are the chosen palette's -
  /// see `CodeTheme`, which carries the syntax palette of whatever scheme is
  /// picked and falls back to the app's default one where a scheme has none.
  final Color codeBackground;
  final Color codeForeground;

  /// Which code theme those blocks are coloured with. A rendered span tree has
  /// its token colours baked into it just as literally as a rendered bubble
  /// does, so the span cache has to be told apart from one built under another
  /// scheme - the same reason the whole palette is in `cacheKey`.
  final String codeThemeId;

  /// The two colours of a diff, and the blocks each half of one is painted on.
  ///
  /// Fixed, like the tool-output green: they are a saying about what happened to
  /// a piece of text - it went in, it came out - not styling. A `+` and a `-`
  /// whose colours move with the user's colour preference stop meaning anything.
  ///
  /// `diffAdded` *is* the tool-output green, deliberately: both mean "text the
  /// agent wrote", and a second green would just be a second green.
  final Color diffAdded;
  final Color diffRemoved;

  /// The code surface with a hint of the signal blended into it. A block of pure
  /// signal colour is a swatch, not code you can read; a block of plain code
  /// surface is indistinguishable from the half of the diff above it.
  final Color addedBlock;
  final Color removedBlock;

  /// Text in a tool card that is not what the card is about: a file path, an
  /// offset, a "Successfully replaced 2 blocks." line.
  ///
  /// `onSurfaceVariant` is the quiet colour, and quiet is not the same as
  /// legible: on a dark card a medium grey lands around 3:1, which is under
  /// what body text needs. So it is [legibleOn] - nudged toward the far end of
  /// the card until it clears 4.5:1, and not a step further. Where the token is
  /// already readable (every light scheme, and most dark ones) this *is* the
  /// token, unchanged; it only bites where the text was genuinely hard to read.
  final Color toolText;
  final Color toolError;

  final Color link;
  final Color error;

  /// Hairline borders (an unreadable image's frame).
  final Color outline;

  /// Inline `code` behind a paragraph, where a real code theme would be too loud.
  final Color inlineCodeBackground;

  factory ChatPalette.from(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final codeBg = CodeTheme.codeSurface(scheme);
    // The text colour of an un-tokened code block, and the token map around it,
    // both from the code theme the chosen scheme carries - raised, in lightness
    // only, against the surface it is actually painted on.
    final code = CodeTheme.of(theme);
    final codeFg = code.foregroundFor(codeBg, appText: scheme.onSurface);
    // The surface a tool card is painted on, bound once: `toolText` and
    // `toolError` are defined *against* it, so the two must be the same card.
    final card = isDark
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainerLow;
    const added = Color(0xFF7FCBA5);
    const addedLight = Color(0xFF2E6B4F);
    const removed = Color(0xFFFF6B6B);
    const removedLight = Color(0xFFB3261E);

    return ChatPalette(
      isDark: isDark,
      assistantBubble: scheme.surfaceContainerHigh,
      userBubble: scheme.primaryContainer,
      assistantAccent: scheme.tertiary,
      userAccent: scheme.primary,
      assistantBody: scheme.onSurface,
      userBody: scheme.onPrimaryContainer,
      muted: scheme.onSurfaceVariant,
      // Lighter than the bubble it sits on, at either brightness - which is how
      // a raised card already read. The token that goes *up* in lightness from
      // `surfaceContainerHigh` is a different one per theme, because the surface
      // scale runs the other way in dark.
      toolCard: card,
      toolResult: isDark ? added : addedLight,
      codeBackground: codeBg,
      codeForeground: codeFg,
      codeThemeId: code.id,
      diffAdded: isDark ? added : addedLight,
      diffRemoved: isDark ? removed : removedLight,
      addedBlock: _tint(codeBg, isDark ? added : addedLight, scheme.onSurface, isDark),
      removedBlock:
          _tint(codeBg, isDark ? removed : removedLight, scheme.onSurface, isDark),
      toolText: legibleOn(scheme.onSurfaceVariant, card),
      toolError: legibleOn(scheme.error, card),
      link: scheme.primary,
      error: scheme.error,
      outline: scheme.outlineVariant,
      // Not a token: an overlay on whatever the text colour is, so it stays a
      // step off the bubble in both themes without picking a hue of its own.
      inlineCodeBackground:
          scheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.08),
    );
  }

  Color bubbleFor(bool assistant) => assistant ? assistantBubble : userBubble;
  Color accentFor(bool assistant) => assistant ? assistantAccent : userAccent;
  Color bodyFor(bool assistant) => assistant ? assistantBody : userBody;

  /// What the rendered-bubble cache has to know about.
  ///
  /// A cached body is a finished subtree of literal `Text`s with the colours
  /// already baked into them. A cache key that only knows the message text and
  /// the brightness would hand back the old colours for content that never
  /// changed - every message in the chat at once - the moment the scheme did.
  int get cacheKey => Object.hashAll([
        isDark,
        codeThemeId,
        assistantBubble,
        userBubble,
        assistantAccent,
        userAccent,
        assistantBody,
        userBody,
        muted,
        toolCard,
        toolResult,
        codeBackground,
        codeForeground,
        diffAdded,
        diffRemoved,
        addedBlock,
        removedBlock,
        toolText,
        toolError,
        link,
        error,
        outline,
        inlineCodeBackground,
      ]);
}

/// [signal] blended into [surface] as strongly as the text on it can take.
///
/// The cap is what a diff block should be: a hint, not a colour swatch. The
/// search *down* from it is because how much a surface can absorb depends on
/// what is read on it - a palette whose body text is near-white can afford a
/// tint that would push a palette whose body text is deliberately a mid grey
/// (Solarized's is) under legible. Same cap for every scheme, and the amount
/// each one actually gets is decided by its own contrast, not by the palette's
/// taste.
Color _tint(Color surface, Color signal, Color text, bool isDark) {
  const floor = 0.03;
  for (var alpha = isDark ? 0.14 : 0.08; alpha > floor; alpha -= 0.01) {
    final candidate =
        Color.alphaBlend(signal.withValues(alpha: alpha), surface);
    if (contrastOn(text, candidate) >= 4.5) return candidate;
  }
  return Color.alphaBlend(signal.withValues(alpha: floor), surface);
}

/// Contrast between two opaque colours, WCAG-style.
double contrastOn(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] nudged toward the far end of [bg] until it clears [target] contrast on
/// it - and no further, so a colour that was already readable stays itself.
///
/// The nudge is toward black or white rather than toward `onSurface`, because
/// what has to be guaranteed is the *contrast*, and the shortest way to it from
/// a medium grey is the nearer pole of the surface it is being read on.
Color legibleOn(Color fg, Color bg, {double target = 4.5}) {
  if (contrastOn(fg, bg) >= target) return fg;
  final pole = bg.computeLuminance() > 0.5 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  for (var t = 0.05; t <= 1.0; t += 0.05) {
    final candidate = Color.lerp(fg, pole, t)!;
    if (contrastOn(candidate, bg) >= target) return candidate;
  }
  return pole;
}
