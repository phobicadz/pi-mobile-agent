import 'package:flutter/material.dart';

import '../utils/theme_mode_store.dart';

/// The app's light/dark choice, held outside the widget tree so `MaterialApp`
/// can be built with it and the toggle can change it without rebuilding `main`.
///
/// It starts as `ThemeMode.system`, which is what a personal app should do. The
/// toggle moves it to an explicit light or dark, and that is stored.
///
/// There is deliberately no way back to `system` from the button. A third state
/// the UI cannot reach is a state users read as the app forgetting its own
/// setting, and following the system again is what a fresh install does anyway.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Flip away from whatever is on screen right now.
  ///
  /// [showing] is the brightness actually being rendered, which the caller reads
  /// from the platform - under `ThemeMode.system` that is the only way to know
  /// which way the toggle needs to go.
  void toggle(Brightness showing) {
    _mode = showing == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    saveThemeMode(_mode);
    notifyListeners();
  }

  /// Load whatever this browser stored, before the first frame is built, so the
  /// app does not open in one theme and then change.
  Future<void> restore() async {
    final stored = await loadThemeMode();
    if (stored == null || stored == _mode) return;
    _mode = stored;
    notifyListeners();
  }
}
