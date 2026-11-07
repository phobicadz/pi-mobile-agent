import 'package:flutter/material.dart';

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
  /// The syntax colours on top of it are still the code theme's. Those are what
  /// make a command or a source file read as one at a glance; the surface is not.
  /// The code theme's own backgrounds are near-neutral greys, and so are these
  /// surfaces whatever the seed, so its token colours stay legible on them.
  final Color codeBackground;
  final Color codeForeground;

  final Color link;
  final Color error;

  /// Hairline borders (an unreadable image's frame).
  final Color outline;

  /// Inline `code` behind a paragraph, where a real code theme would be too loud.
  final Color inlineCodeBackground;

  factory ChatPalette.from(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

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
      toolCard: isDark
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainerLow,
      toolResult: isDark ? const Color(0xFF7FCBA5) : const Color(0xFF2E6B4F),
      codeBackground: isDark
          ? scheme.surfaceContainer
          : scheme.surfaceContainerLowest,
      codeForeground: scheme.onSurface,
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
        link,
        error,
        outline,
        inlineCodeBackground,
      ]);
}
