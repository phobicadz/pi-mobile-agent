import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/utils/chat_palette.dart';
import 'package:pi_mobile_agent/utils/code_theme.dart';
import 'package:pi_mobile_agent/utils/editor_palettes.dart';

/// The authored editor palettes, and what the app must still be able to promise
/// after it stops generating everything from a seed.
///
/// A generated scheme gets its contrast pairs from the generator. An authored one
/// has to earn them here, so every claim a generated scheme gives for free is
/// checked against the palettes this file adds - at both brightnesses, because a
/// palette that is legible in dark mode only is half a palette.
const _authored = <AppColorScheme, (EditorPalette, EditorPalette?)>{
  AppColorScheme.atomOne: (EditorPalette.atomOneDark, EditorPalette.atomOneLight),
  AppColorScheme.solarized: (EditorPalette.solarizedDark, EditorPalette.solarizedLight),
  AppColorScheme.github: (EditorPalette.githubDark, EditorPalette.githubLight),
  AppColorScheme.nord: (EditorPalette.nord, null),
  AppColorScheme.catppuccin: (EditorPalette.catppuccinMocha, null),
  AppColorScheme.tokyoNight: (EditorPalette.tokyoNight, null),
  AppColorScheme.monokai: (EditorPalette.monokai, null),
};

double _hue(Color color) => HSLColor.fromColor(color).hue;

/// A theme built the way `main.dart` builds it.
///
/// The code theme travels on the `ThemeData`, so a test that builds a bare one
/// is testing a chat whose code is always the app default - which is a fact worth
/// knowing before it is mistaken for the scheme's own.
ThemeData _themeFor(AppColorScheme scheme, Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: scheme.schemeFor(brightness),
      brightness: brightness,
      extensions: [CodeTheme.following(scheme, brightness)],
    );

void main() {
  test('every editor theme the enum offers is one this file knows', () {
    // The enum and this table are two ways of naming the same thing, and a new
    // theme added to one and not the other is a theme no test has looked at.
    expect(AppColorScheme.values.where((s) => s.isDarkOnly || _authored.containsKey(s)),
        isNotEmpty);
    for (final scheme in AppColorScheme.values) {
      final family = _authored[scheme];
      if (family == null) continue;
      expect(scheme.isDarkOnly, family.$2 == null,
          reason: '${scheme.displayName}: the enum says ${scheme.isDarkOnly ? 'dark only' : 'has a light half'}, '
              'the palette says otherwise');
    }
    for (final scheme in AppColorScheme.values.where((s) => s.isDarkOnly)) {
      expect(scheme.note, contains('dark palette'), reason: scheme.name);
    }
    for (final scheme in AppColorScheme.values.where((s) => !s.isDarkOnly)) {
      expect(scheme.note, isNull, reason: '${scheme.name} has a light half');
    }
  });

  test('an editor theme paints with the palette it is named after', () {
    for (final entry in _authored.entries) {
      final scheme = entry.key;
      final dark = entry.value.$1;
      final light = entry.value.$2;

      final built = scheme.schemeFor(Brightness.dark);
      expect(built.surface, dark.background,
          reason: '${dark.name}: the background *is* the theme. A scheme seeded '
              'from its accent would generate its own neutral scale instead, '
              'which is the whole reason this file exists');
      expect(built.onSurface, dark.foreground, reason: dark.name);
      expect(built.tertiary, isNot(built.primary), reason: dark.name);

      if (light != null) {
        final builtLight = scheme.schemeFor(Brightness.light);
        expect(builtLight.surface, light.background, reason: light.name);
        expect(builtLight.onSurface, light.foreground, reason: light.name);
      } else {
        // No light half to be faithful to: say so by generating one from the
        // theme's hue rather than painting a light mode with dark surfaces.
        final builtLight = scheme.schemeFor(Brightness.light);
        expect(builtLight.surface.computeLuminance(),
            greaterThan(built.surface.computeLuminance()),
            reason: '${dark.name} in light mode is a light app, not a dark '
                'palette with a light label');
      }
    }
  });

  test('every palette keeps its hue when it is made legible', () {
    // `legibleOn` moves a colour toward black or white, which scales a colour's
    // channels without changing which one is dominant: lightness, never hue. A
    // palette whose accent got *replaced* to pass a contrast test would be a
    // different theme with the old theme's name.
    for (final entry in _authored.entries) {
      for (final brightness in Brightness.values) {
        final palette = brightness == Brightness.dark ? entry.value.$1 : entry.value.$2;
        if (palette == null) continue;
        final built = entry.key.schemeFor(brightness);
        final what = '${palette.name} / $brightness';

        for (final pair in {
          'primary': palette.primary,
          'tertiary': palette.tertiary,
          'error': palette.error,
        }.entries) {
          final actual = switch (pair.key) {
            'primary' => built.primary,
            'tertiary' => built.tertiary,
            _ => built.error,
          };
          expect((_hue(actual) - _hue(pair.value)).abs(), lessThan(1.0),
              reason: '$what ${pair.key}: the accent moved in lightness, not in '
                  'hue');
        }
      }
    }
  });

  test('the chat is legible on every palette, at both brightnesses', () {
    for (final scheme in AppColorScheme.values) {
      for (final brightness in Brightness.values) {
        final theme = _themeFor(scheme, brightness);
        final chat = ChatPalette.from(theme);
        final built = theme.colorScheme;
        final what = '${scheme.displayName} / $brightness';

        // Each of these is one thing the chat actually draws.
        final pairs = <String, (Color, Color)>{
          'a reply’s text': (built.onSurface, chat.assistantBubble),
          'the Pi accent': (built.tertiary, chat.assistantBubble),
          'your text': (built.onPrimaryContainer, chat.userBubble),
          'the quiet text in a card': (chat.toolText, chat.toolCard),
          // The compact view draws its one line straight onto the reply, with no
          // card between them - a different surface, so a different measurement.
          'a file line in the compact view': (chat.fileLine, chat.assistantBubble),
          // The tool-result green, drawn on a reply instead of on a code block.
          // It is the same green the full card uses - it means the same thing -
          // so it has to clear the same bar on a surface nobody chose for it.
          'a command’s output in the compact view':
              (chat.outputPreview, chat.assistantBubble),
          'an error': (chat.error, chat.assistantBubble),
          'a command on its block': (chat.codeForeground, chat.codeBackground),
          'an added half of a diff': (chat.codeForeground, chat.addedBlock),
          'a removed half of a diff': (chat.codeForeground, chat.removedBlock),
        };

        for (final entry in pairs.entries) {
          expect(contrastOn(entry.value.$1, entry.value.$2),
              greaterThanOrEqualTo(4.5),
              reason: '$what: ${entry.key} is text a person has to read');
        }

        // The two roles, in the only two ways the chat tells them apart.
        expect(built.tertiary, isNot(built.primary),
            reason: '$what: Pi and You are told apart by hue');
        expect(chat.userBubble, isNot(chat.assistantBubble),
            reason: '$what: and by the bubble fill');
      }
    }
  });

  test('an authored palette’s two accents are two hues apart, not one hue '
      'wearing two names', () {
    // The chat's only visual distinction is "your side is this hue, Pi's side is
    // that one". A generated scheme gets that from the palette's hue rotation;
    // an authored one only has it if the two colours picked are actually apart.
    for (final entry in _authored.entries) {
      for (final brightness in Brightness.values) {
        final palette = brightness == Brightness.dark ? entry.value.$1 : entry.value.$2;
        if (palette == null) continue;
        final built = entry.key.schemeFor(brightness);
        var apart = (_hue(built.primary) - _hue(built.tertiary)).abs() % 360;
        apart = apart > 180 ? 360 - apart : apart;
        expect(apart, greaterThanOrEqualTo(45),
            reason: '${palette.name} / $brightness: ${apart.round()}° between '
                'the two roles is not a distinction a reader on a phone will '
                'see');
      }
    }
  });

  test('a card is still a step off the bubble it sits in, in every palette',
      () {
    for (final scheme in AppColorScheme.values) {
      for (final brightness in Brightness.values) {
        final chat = ChatPalette.from(_themeFor(scheme, brightness));
        final step = (chat.toolCard.computeLuminance() -
                chat.assistantBubble.computeLuminance())
            .abs();
        expect(step, greaterThan(0.002),
            reason: '${scheme.displayName} / $brightness: a card the same colour '
                'as the bubble around it is not a card');
      }
    }
  });
}
