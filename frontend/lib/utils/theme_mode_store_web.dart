import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';

const _key = 'pi-mobile-agent.theme';

/// Read back the stored choice, or null when there is none - which is the app
/// following the system, not the app having forgotten.
///
/// Wrapped in a try because a browser can refuse storage outright (private
/// mode, blocked cookies). A theme that defaults to the system is a working
/// theme; a theme that throws on startup is not.
Future<ThemeMode?> loadThemeMode() async {
  try {
    final value = globalContext['localStorage'];
    if (value == null || !value.isA<JSObject>()) return null;
    final stored =
        (value as JSObject).callMethod<JSAny?>('getItem'.toJS, _key.toJS);
    if (stored == null || !stored.isA<JSString>()) return null;
    return _decode((stored as JSString).toDart);
  } catch (_) {
    return null;
  }
}

void saveThemeMode(ThemeMode mode) {
  try {
    final value = globalContext['localStorage'];
    if (value == null || !value.isA<JSObject>()) return;
    (value as JSObject)
        .callMethod<JSAny?>('setItem'.toJS, _key.toJS, _encode(mode).toJS);
  } catch (_) {
    // The choice still applies for this session; only remembering it failed.
  }
}

String _encode(ThemeMode mode) => switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };

ThemeMode? _decode(String stored) => switch (stored) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => null,
    };
