import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

import 'dom_geometry_web.dart';

/// Ask the browser for the whole screen, and reserve the safe areas it reports.
///
/// Flutter Web writes its own `<meta name="viewport">` and drops the one in
/// `web/index.html`, and the one it writes has no `viewport-fit`. On an iPhone
/// that means the page stops short of the status bar and of the home indicator:
/// the app is full width but not full length. Adding `viewport-fit=cover` asks
/// the page to extend under both.
///
/// Asking is not the same as getting it, and the app cannot assume it: Flutter
/// Web reports no safe areas of its own (`MediaQuery.padding` is empty on the
/// web), so the app has to learn them from the browser and reserve them.
///
/// It used to subtract, from each inset, the distance between the reported safe
/// area and Flutter's own element - an element measured at y=47 with a 47px
/// inset reported looked like a browser that had already kept the status bar out
/// of the canvas, and reserving it again would have been the same space twice.
/// That reading was wrong, and the phone said so: with the top inset no longer
/// reserved, the app bar sat under the status bar and the buttons in it were
/// unreadable. The two measurements are not in the same coordinate space - the
/// same sample reports the visual viewport at `offsetTop -47`, so a rect read in
/// document coordinates says nothing about where that rectangle is on the screen.
/// The browser's own safe-area numbers are the only ones here that describe the
/// screen, so they are what the layout reserves. `PageGeometry` stays for
/// measurement and diagnostics, not for layout.
ValueNotifier<EdgeInsets> useBrowserSafeArea() {
  final notifier = ValueNotifier<EdgeInsets>(EdgeInsets.zero);
  _SafeAreaTracker(notifier).start();
  return notifier;
}

/// Measures once, then again whenever the viewport changes: rotating a phone
/// moves the left/right insets, an iOS browser changes them when a keyboard or a
/// toolbar appears, and a viewport tag edited after load is applied whenever the
/// browser feels like it.
class _SafeAreaTracker extends WidgetsBindingObserver {
  _SafeAreaTracker(this._notifier);

  final ValueNotifier<EdgeInsets> _notifier;

  void start() {
    try {
      _requestFullViewport();
      // The browser applies a viewport change on its own schedule, and the
      // element's position is what the measurement depends on: sample again
      // after it has had the chance to move things.
      Timer(const Duration(milliseconds: 500), _measure);
      Timer(const Duration(seconds: 2), _measure);
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
      final insets = readPageGeometry().cssInsets;
      if (insets != _notifier.value) _notifier.value = insets;
    } catch (_) {
      // Keep whatever was measured last; a wrong inset is better than none.
    }
  }
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

JSObject _global(String property) {
  final value = globalContext[property];
  if (value == null || !value.isA<JSObject>()) {
    throw StateError('no $property on the page');
  }
  return value as JSObject;
}
