import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';

const _themeKey = 'pi-mobile-agent.theme';
const _fontKey = 'pi-mobile-agent.fontScale';
const _fileFontKey = 'pi-mobile-agent.fileFontScale';

/// Read back the stored theme, or null when there is none - which is the app
/// following the system, not the app having forgotten.
Future<ThemeMode?> loadThemeMode() async => switch (_read(_themeKey)) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => null,
    };

void saveThemeMode(ThemeMode mode) => _write(
    _themeKey,
    switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    });

/// Read back the stored text size, or null when there is none. A value this
/// version cannot read parses to null and the app starts at its default size,
/// which is what an unreadable stored value should mean.
Future<double?> loadFontScale() async => double.tryParse(_read(_fontKey) ?? '');

void saveFontScale(double scale) => _write(_fontKey, scale.toString());

/// The file viewer's text size, stored separately from the chat's: 12px
/// monospace code and chat prose are two different things to read, and a phone
/// usually wants them at different sizes. See `AppearanceController`.
Future<double?> loadFileFontScale() async =>
    double.tryParse(_read(_fileFontKey) ?? '');

void saveFileFontScale(double scale) => _write(_fileFontKey, scale.toString());

/// Storage can be refused outright (private mode, blocked cookies), and an app
/// that throws on startup over its text size is not an app - one that falls back
/// to its default is.
String? _read(String key) {
  try {
    final storage = globalContext['localStorage'];
    if (storage == null || !storage.isA<JSObject>()) return null;
    final value =
        (storage as JSObject).callMethod<JSAny?>('getItem'.toJS, key.toJS);
    return value != null && value.isA<JSString>()
        ? (value as JSString).toDart
        : null;
  } catch (_) {
    return null;
  }
}

void _write(String key, String value) {
  try {
    final storage = globalContext['localStorage'];
    if (storage == null || !storage.isA<JSObject>()) return;
    (storage as JSObject)
        .callMethod<JSAny?>('setItem'.toJS, key.toJS, value.toJS);
  } catch (_) {
    // The choice still applies for this session; only remembering it failed.
  }
}
