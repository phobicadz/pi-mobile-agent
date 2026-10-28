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
/// unreadable. The two measurements were not in the same coordinate space - the
/// same sample reported the visual viewport at `offsetTop -47`.
///
/// They are now. The page is pinned to the visual viewport, so a rect on the page
/// and the area the user is looking at are the same thing, and what the layout
/// reserves is the part of each safe area that falls *inside* Flutter's canvas -
/// `PageGeometry.overlappedInsets`. Those are the same numbers as the browser's
/// own only when the canvas starts at the top of the screen, and it deliberately
/// does not any more: iOS will not let the canvas be any height other than the
/// screen minus the status bar (see `web/index.html`), so the canvas starts below
/// it. Reserving the status bar again inside a canvas that already begins under it
/// is the same 47px counted twice.
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
      _pinDocumentToWindow();
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
      _pinDocumentToWindow();
      // The areas inside the canvas, not the areas the browser reports. Those are
      // only the same numbers when the canvas starts at the top of the screen,
      // and it no longer does.
      final insets = readPageGeometry().overlappedInsets;
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
  final existing = document.callMethod<JSAny?>(
      'querySelector'.toJS, 'meta[name="viewport"]'.toJS);

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

/// Size the root element to the window, using the numbers the browser gives for
/// its own window.
///
/// Done from Dart as well as from `web/index.html` for two reasons. An installed
/// app on iOS serves its own cached page shell while re-fetching its code, so a
/// rule written into the HTML can simply not arrive on the phone - which is what
/// the measurements said had happened. And the window changes when a keyboard
/// opens or a phone rotates, which is the same moment the app is already
/// re-measuring everything else.
void _pinDocumentToWindow() {
  final inner = globalContext['innerHeight'];
  if (inner == null || !inner.isA<JSNumber>()) return;
  final height = (inner as JSNumber).toDartDouble.toInt();
  if (height <= 0) return;
  final style = _rootStyle();
  if (style == null) return;
  style['height'] = '${height}px'.toJS;
}

/// Paint the page that sits behind Flutter's canvas.
///
/// On iOS the canvas can end up shorter than the screen it is drawn on, and the
/// space left over is the browser's to paint - white, unless the app says
/// otherwise. Matching the colour the app paints its own bottom edge with is what
/// stops that reading as a band across the bottom of the screen.
void paintPageBehindCanvas(Color colour) {
  final style = _rootStyle();
  if (style == null) return;
  style['background'] = _cssColour(colour).toJS;
}

JSObject? _rootStyle() {
  final document = globalContext['document'];
  if (document == null || !document.isA<JSObject>()) return null;
  final root = (document as JSObject)['documentElement'];
  if (root == null || !root.isA<JSObject>()) return null;
  final style = (root as JSObject)['style'];
  return style != null && style.isA<JSObject>() ? style as JSObject : null;
}

/// A Flutter colour as CSS. Integers rather than the colour's floats, because a
/// page background is the one place an approximation would be visible.
String _cssColour(Color colour) {
  final argb = colour.toARGB32();
  final alpha = (argb >> 24) & 0xff;
  final red = (argb >> 16) & 0xff;
  final green = (argb >> 8) & 0xff;
  final blue = argb & 0xff;
  return alpha == 0xff
      ? 'rgb($red,$green,$blue)'
      : 'rgba($red,$green,$blue,${(alpha / 255).toStringAsFixed(3)})';
}

JSObject _global(String property) {
  final value = globalContext[property];
  if (value == null || !value.isA<JSObject>()) {
    throw StateError('no $property on the page');
  }
  return value as JSObject;
}
