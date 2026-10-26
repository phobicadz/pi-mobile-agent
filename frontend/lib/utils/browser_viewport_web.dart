import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

/// Ask the browser for the whole screen, and keep its safe areas in step.
///
/// Flutter Web writes its own `<meta name="viewport">` and drops the one in
/// `web/index.html`, and the one it writes has no `viewport-fit`. On an iPhone
/// that means the page stops short of the status bar and of the home indicator:
/// the app is full width but not full length. Adding `viewport-fit=cover` makes
/// the page extend under both.
///
/// Covering them hands the safe areas to the app, because Flutter Web has no
/// idea they exist - `MediaQuery.padding` on the web is empty. The only way to
/// learn them is to have the browser resolve `env(safe-area-inset-*)` on an
/// element and read the computed padding back, which is what `_readSafeArea`
/// does. Both steps are what make the app run the full length of the screen on
/// iOS without drawing the prompt field under the home indicator.
ValueNotifier<EdgeInsets> useBrowserSafeArea() {
  final notifier = ValueNotifier<EdgeInsets>(EdgeInsets.zero);
  _SafeAreaTracker(notifier).start();
  return notifier;
}

/// Measures the safe areas once, then again whenever the viewport changes:
/// rotating the phone moves the left/right insets, and an iOS browser changes
/// them when a keyboard or a toolbar appears.
class _SafeAreaTracker extends WidgetsBindingObserver {
  _SafeAreaTracker(this._notifier);

  final ValueNotifier<EdgeInsets> _notifier;

  void start() {
    try {
      _requestFullViewport();
    } catch (_) {
      // A browser that will not budge keeps its default viewport configuration.
    }
    _measure();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => _measure();

  void _measure() {
    try {
      final insets = _readSafeArea();
      if (insets != _notifier.value) _notifier.value = insets;
    } catch (_) {
      // Keep whatever was measured last; a wrong inset is better than none.
    }
  }
}

JSObject _global(String property) {
  final value = globalContext[property];
  if (value == null || !value.isA<JSObject>()) {
    throw StateError('no $property on the page');
  }
  return value as JSObject;
}

/// Flutter's own viewport meta, plus `viewport-fit=cover`.
///
/// Rewriting Flutter's tag rather than adding one to `web/index.html`: the
/// engine removes any tag it finds there and writes its own.
void _requestFullViewport() {
  final document = _global('document');
  final existing =
      document.callMethod<JSAny?>('querySelector'.toJS, 'meta[name="viewport"]'.toJS);

  JSObject meta;
  if (existing != null && existing.isA<JSObject>()) {
    meta = existing as JSObject;
  } else {
    final head = document['head'];
    if (head == null || !head.isA<JSObject>()) return;
    final created =
        document.callMethod<JSObject>('createElement'.toJS, 'meta'.toJS);
    created['name'] = 'viewport'.toJS;
    (head as JSObject).callMethod<JSAny?>('appendChild'.toJS, created);
    meta = created;
  }

  final current = meta['content'];
  final content = current.isA<JSString>() ? (current as JSString).toDart : '';
  if (content.contains('viewport-fit')) return;
  final updated = content.isEmpty
      ? 'width=device-width, initial-scale=1.0, viewport-fit=cover'
      : '$content, viewport-fit=cover';
  meta['content'] = updated.toJS;
}

EdgeInsets _readSafeArea() {
  final document = _global('document');
  final body = document['body'];
  if (body == null || !body.isA<JSObject>()) return EdgeInsets.zero;
  final bodyElement = body as JSObject;

  // env() only resolves as a computed value on a real element in the page.
  final probe = document.callMethod<JSObject>('createElement'.toJS, 'div'.toJS);
  final style = probe['style'];
  if (style == null || !style.isA<JSObject>()) return EdgeInsets.zero;
  (style as JSObject)['cssText'] = ('position:fixed;top:0;left:0;width:0;height:0;'
          'visibility:hidden;pointer-events:none;'
          'padding-top:env(safe-area-inset-top);'
          'padding-right:env(safe-area-inset-right);'
          'padding-bottom:env(safe-area-inset-bottom);'
          'padding-left:env(safe-area-inset-left);')
      .toJS;

  bodyElement.callMethod<JSAny?>('appendChild'.toJS, probe);
  final computed = globalContext.callMethod<JSAny?>('getComputedStyle'.toJS, probe);
  final insets = EdgeInsets.only(
    top: _pixels(computed, 'paddingTop'),
    right: _pixels(computed, 'paddingRight'),
    bottom: _pixels(computed, 'paddingBottom'),
    left: _pixels(computed, 'paddingLeft'),
  );
  bodyElement.callMethod<JSAny?>('removeChild'.toJS, probe);
  return insets;
}

double _pixels(JSAny? style, String property) {
  if (style == null || !style.isA<JSObject>()) return 0;
  final value = (style as JSObject)[property];
  if (!value.isA<JSString>()) return 0;
  return double.tryParse((value as JSString).toDart.replaceAll('px', '').trim()) ??
      0;
}
