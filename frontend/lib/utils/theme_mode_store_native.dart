import 'package:flutter/material.dart';

/// Native builds do not remember the light/dark choice.
///
/// There is nowhere to put it without another dependency. Android and iOS both
/// sandbox the app's writable storage behind a plugin (`path_provider`), and
/// writing to a path from `Platform.environment` works on a desktop and fails on
/// a phone - which is worse than not trying, because it looks like a
/// persistence feature that only works half the time.
///
/// So the choice holds for the session and the next launch follows the system
/// again. The web build, which is the one a phone actually runs this app from,
/// keeps it properly.

Future<ThemeMode?> loadThemeMode() async => null;

void saveThemeMode(ThemeMode mode) {}
