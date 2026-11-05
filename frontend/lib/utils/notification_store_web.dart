import 'dart:js_interop';
import 'dart:js_interop_unsafe';

const _enabledKey = 'pi-mobile-agent.notifications';

/// Read back the stored choice, or null when there is none - which is the app
/// at its default, not the app having forgotten.
Future<bool?> loadNotificationsEnabled() async => switch (_read(_enabledKey)) {
      'true' => true,
      'false' => false,
      _ => null,
    };

void saveNotificationsEnabled(bool enabled) =>
    _write(_enabledKey, enabled ? 'true' : 'false');

/// Storage can be refused outright (private mode, blocked cookies), and an app
/// that throws on startup over a notification setting is not an app - one that
/// falls back to its default is.
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
