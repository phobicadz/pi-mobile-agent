import 'package:flutter/material.dart';

import '../utils/appearance_store.dart';

/// How the app looks: which theme it uses and how large the chat text is.
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
  int _fontLevel = 0;
  int _fileFontLevel = 0;

  ThemeMode get themeMode => _themeMode;

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

    final storedScale = await loadFontScale();
    if (storedScale != null) _fontLevel = _levelFor(storedScale);

    final storedFileScale = await loadFileFontScale();
    if (storedFileScale != null) _fileFontLevel = _levelFor(storedFileScale);

    if (storedTheme != null || storedScale != null || storedFileScale != null) {
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
