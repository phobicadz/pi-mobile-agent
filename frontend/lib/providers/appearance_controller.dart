import 'package:flutter/material.dart';

import '../utils/appearance_store.dart';
import '../utils/dracula_scheme.dart';
import '../utils/editor_palettes.dart';

/// Available color schemes for the app.
///
/// The first five are seeds - a hue to generate a Material 3 scheme from. The
/// rest are palettes an editor names: Dracula, and the editor themes held in
/// `EditorPalette` (Atom One, Solarized, GitHub, Nord, Catppuccin, Tokyo Night,
/// Monokai). Those are authored from the colours the theme itself publishes,
/// because a hue is not what someone means when they ask for Solarized, and a
/// generated scheme will not produce it (see utils/editor_palettes.dart).
///
/// Adding one is a case here plus that palette's values in `EditorPalette`: the
/// picker, the stored choice and the tests all follow the enum.
enum AppColorScheme {
  blue,
  green,
  purple,
  orange,
  red,
  dracula,
  atomOne,
  solarized,
  github,
  nord,
  catppuccin,
  tokyoNight,
  monokai,
}

/// An editor theme's dark half, and its light half where the theme ships one.
typedef _EditorFamily = ({EditorPalette dark, EditorPalette? light});

extension AppColorSchemeExt on AppColorScheme {
  /// Display name for the color scheme.
  String get displayName => switch (this) {
        AppColorScheme.blue => 'Blue',
        AppColorScheme.green => 'Green',
        AppColorScheme.purple => 'Purple',
        AppColorScheme.orange => 'Orange',
        AppColorScheme.red => 'Red',
        AppColorScheme.dracula => 'Dracula',
        AppColorScheme.atomOne => 'Atom One',
        AppColorScheme.solarized => 'Solarized',
        AppColorScheme.github => 'GitHub',
        AppColorScheme.nord => 'Nord',
        AppColorScheme.catppuccin => 'Catppuccin',
        AppColorScheme.tokyoNight => 'Tokyo Night',
        AppColorScheme.monokai => 'Monokai',
      };

  /// Seed color for Material 3 color generation - and the colour that stands for
  /// this scheme wherever the picker shows one.
  Color get seedColor => switch (this) {
        AppColorScheme.blue => Colors.blue,
        AppColorScheme.green => Colors.green,
        AppColorScheme.purple => Colors.deepPurple,
        AppColorScheme.orange => Colors.orange,
        AppColorScheme.red => Colors.red,
        AppColorScheme.dracula => Dracula.purple,
        _ => _family!.dark.primary,
      };

  /// Whether this palette has a light version at all.
  ///
  /// A seeded scheme has one by construction. An editor theme has one only when
  /// the theme itself ships one: Solarized is designed as a pair, Atom One and
  /// GitHub ship light variants, and Nord, Catppuccin, Tokyo Night and Monokai
  /// are dark themes with no light half to be faithful to.
  bool get isDarkOnly => switch (this) {
        AppColorScheme.dracula => true,
        _ => _family != null && _family!.light == null,
      };

  /// The scheme this choice produces at a given brightness.
  ///
  /// Authored where an authored palette exists at that brightness, and generated
  /// from the palette's own hue where it does not - which is the honest answer
  /// for a dark-only theme in light mode, and is said out loud in the picker
  /// (`note`) rather than left for someone to discover by picking it and
  /// wondering.
  ColorScheme schemeFor(Brightness brightness) {
    if (this == AppColorScheme.dracula && brightness == Brightness.dark) {
      return Dracula.darkScheme();
    }
    final authored = authoredAt(brightness);
    if (authored != null) return authored.schemeFor(brightness);
    return ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  }

  /// The authored palette this choice has at this brightness, or null.
  ///
  /// Public because the *code* theme has the same question: a scheme with an
  /// authored palette at this brightness has that palette's syntax colours too,
  /// and one without has no syntax palette to follow. `CodeTheme.following` asks
  /// this rather than guessing from the seed.
  EditorPalette? authoredAt(Brightness brightness) => switch (brightness) {
        Brightness.dark => _family?.dark,
        Brightness.light => _family?.light,
      };

  /// Anything the picker has to say about this choice, or null when the name and
  /// the swatch are the whole of it.
  String? get note {
    if (this == AppColorScheme.dracula) {
      return 'A dark palette: in dark mode this is Dracula’s own surfaces and accents, '
          'in light mode its purple on a light surface';
    }
    if (!isDarkOnly) return null;
    return 'A dark palette: ${_family!.dark.name} has no light version, so in '
        'light mode this is its own accent on a light surface';
  }

  _EditorFamily? get _family => switch (this) {
        AppColorScheme.atomOne => (
            dark: EditorPalette.atomOneDark,
            light: EditorPalette.atomOneLight,
          ),
        AppColorScheme.solarized => (
            dark: EditorPalette.solarizedDark,
            light: EditorPalette.solarizedLight,
          ),
        AppColorScheme.github => (
            dark: EditorPalette.githubDark,
            light: EditorPalette.githubLight,
          ),
        AppColorScheme.nord => (dark: EditorPalette.nord, light: null),
        AppColorScheme.catppuccin => (
            dark: EditorPalette.catppuccinMocha,
            light: null,
          ),
        AppColorScheme.tokyoNight => (
            dark: EditorPalette.tokyoNight,
            light: null,
          ),
        AppColorScheme.monokai => (dark: EditorPalette.monokai, light: null),
        AppColorScheme.blue ||
        AppColorScheme.green ||
        AppColorScheme.purple ||
        AppColorScheme.orange ||
        AppColorScheme.red ||
        AppColorScheme.dracula =>
          null,
      };
}

/// How the app looks: which theme it uses, color scheme, and how large the chat text is.
///
/// Held outside the widget tree so `MaterialApp` can be built with it and the
/// app bar can change it, rather than the setting living inside one screen.
///
/// Both start at the app's designed defaults - follow the system, chat at the
/// size it was laid out for. The controls move away from those, and the web
/// build stores where they ended up.
///
/// There is deliberately no way back to `ThemeMode.system` from the button. A
/// third state the UI cannot reach is a state users read as the app forgetting
/// its own setting, and following the system again is what a fresh install does
/// anyway.
class AppearanceController extends ChangeNotifier {
  /// Text size counted in steps from the size the chat was designed at, rather
  /// than adding 0.1 each press - that is how 1.3 becomes 1.2999999999999998,
  /// and a size that does not match its stored value is its own kind of bug.
  static const _step = 0.1;
  static const _minLevel = -2;
  static const _maxLevel = 8;

  ThemeMode _themeMode = ThemeMode.system;
  AppColorScheme _colorScheme = AppColorScheme.blue;
  int _fontLevel = 0;
  int _fileFontLevel = 0;

  ThemeMode get themeMode => _themeMode;

  AppColorScheme get colorScheme => _colorScheme;

  /// What every size in the chat is multiplied by. 1.0 is the size the bubbles
  /// were laid out for.
  double get fontScale => 1.0 + _fontLevel * _step;

  /// The buttons say which directions are left, rather than pressing and
  /// watching nothing happen at the end of the range.
  bool get canIncreaseFont => _fontLevel < _maxLevel;
  bool get canDecreaseFont => _fontLevel > _minLevel;

  /// The file viewer's text size, counted the same way.
  ///
  /// Separate from the chat's on purpose: a file is 12px monospace code, which
  /// is a different thing to read from chat prose at a different size, and a
  /// phone usually wants them apart. Making one button change both is how a
  /// "make it bigger" request ends up making the wrong thing bigger.
  double get fileFontScale => 1.0 + _fileFontLevel * _step;

  bool get canIncreaseFileFont => _fileFontLevel < _maxLevel;
  bool get canDecreaseFileFont => _fileFontLevel > _minLevel;

  void changeFileFont({required bool larger}) {
    final level = _fileFontLevel + (larger ? 1 : -1);
    if (level < _minLevel || level > _maxLevel) return;
    _fileFontLevel = level;
    saveFileFontScale(fileFontScale);
    notifyListeners();
  }

  /// Change the color scheme and persist the choice.
  void setColorScheme(AppColorScheme scheme) {
    if (_colorScheme == scheme) return;
    _colorScheme = scheme;
    saveColorScheme(scheme);
    notifyListeners();
  }

  /// Flip away from whatever is on screen right now.
  ///
  /// [showing] is the brightness actually being rendered, which the caller reads
  /// from the theme - under `ThemeMode.system` the platform is the only way to
  /// know which way the toggle needs to go, and once a choice has been made the
  /// platform is not what is on the screen at all.
  void toggleTheme(Brightness showing) {
    _themeMode = showing == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    saveThemeMode(_themeMode);
    notifyListeners();
  }

  void changeFont({required bool larger}) {
    final level = _fontLevel + (larger ? 1 : -1);
    if (level < _minLevel || level > _maxLevel) return;
    _fontLevel = level;
    saveFontScale(fontScale);
    notifyListeners();
  }

  /// Load whatever this browser stored, before the first frame is built, so the
  /// app does not open at one size and theme and then change.
  Future<void> restore() async {
    final storedTheme = await loadThemeMode();
    if (storedTheme != null) _themeMode = storedTheme;

    final storedColorScheme = await loadColorScheme();
    if (storedColorScheme != null) _colorScheme = storedColorScheme;

    final storedScale = await loadFontScale();
    if (storedScale != null) _fontLevel = _levelFor(storedScale);

    final storedFileScale = await loadFileFontScale();
    if (storedFileScale != null) _fileFontLevel = _levelFor(storedFileScale);

    if (storedTheme != null ||
        storedColorScheme != null ||
        storedScale != null ||
        storedFileScale != null) {
      notifyListeners();
    }
  }

  int _levelFor(double scale) {
    final level = ((scale - 1.0) / _step).round();
    if (level < _minLevel) return _minLevel;
    if (level > _maxLevel) return _maxLevel;
    return level;
  }
}
