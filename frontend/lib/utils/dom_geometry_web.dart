import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

/// The page geometry the app measures itself with, read from the browser.
///
/// Two different things live here and the app needs both of them: the safe areas
/// the browser reports (`env(safe-area-inset-*)`), and where Flutter's own
/// element actually sits on the page. The first is what the layout reserves; the
/// second is what makes a layout problem on a phone visible in the logs. They
/// cannot be subtracted from each other - see [PageGeometry.overlappedInsets].
class PageGeometry {
  PageGeometry({
    required this.cssInsets,
    required this.hostRect,
    required this.innerWidth,
    required this.innerHeight,
    required this.clientWidth,
    required this.clientHeight,
    required this.visualWidth,
    required this.visualHeight,
    required this.visualOffsetTop,
    required this.visualScale,
    required this.rootInlineHeight,
    required this.rootComputedHeight,
    required this.viewportMeta,
    required this.devicePixelRatio,
  });

  /// What the browser says the safe areas are.
  final EdgeInsets cssInsets;

  /// Flutter's element on the page, in layout pixels, or null if it was not
  /// found.
  final Rect? hostRect;

  final double innerWidth;
  final double innerHeight;

  /// The document element's own box, which is what Flutter Web sizes its view
  /// from on iOS - see `full_page_dimensions_provider.dart` in the engine.
  final double clientWidth;
  final double clientHeight;

  /// The part of the page the user can actually see. On iOS this is what shrinks
  /// when the keyboard opens, while the layout viewport keeps its height.
  final double visualWidth;
  final double visualHeight;
  final double visualOffsetTop;
  final double visualScale;

  /// What the root element's own inline `height` says, and what it ended up as.
  ///
  /// The app sizes the page from `window.innerHeight` because on iOS `100dvh`
  /// resolves to something else, and the engine reads the root element's box.
  /// Those two facts only meet once, at the page load, so when the band is still
  /// there the question is which of them won - and nothing else in these numbers
  /// can answer it. `rootInlineHeight` being empty means the sizing never
  /// reached this page; a number there with a different `rootComputedHeight`
  /// means the browser overrode it.
  final String rootInlineHeight;
  final double rootComputedHeight;

  /// The viewport tag in force, which is what decides whether the page is asked
  /// to draw under the safe areas at all.
  final String viewportMeta;

  final double devicePixelRatio;

  /// The part of each safe area that falls inside Flutter's element.
  ///
  /// This is what the layout reserves. It was not, once, and the reason it wasn't
  /// is the reason it is now: the element rect is read in *document* coordinates
  /// while the safe areas belong to the *screen*, and while the page could scroll
  /// those two were a different distance apart - a sample reporting the visual
  /// viewport at `offsetTop -47` shows it. The page is pinned to the visual
  /// viewport now, so they coincide and the overlap says what it appears to say.
  ///
  /// The far edges are measured the other way round: how much page is left between
  /// the element and the edge of the window is how much of that inset the browser
  /// already kept out of the canvas.
  EdgeInsets get overlappedInsets {
    final host = hostRect;
    if (host == null) return cssInsets; // nothing measured: assume all of them
    return EdgeInsets.only(
      top: _overlap(cssInsets.top, host.top),
      left: _overlap(cssInsets.left, host.left),
      // The far edges: how much page is left between the element and the edge of
      // the window is how much of the inset the browser already kept out.
      right: _overlap(cssInsets.right, innerWidth - host.right),
      bottom: _overlap(cssInsets.bottom, innerHeight - host.bottom),
    );
  }

  static double _overlap(double inset, double keptOutOfTheCanvas) {
    final owned = inset - keptOutOfTheCanvas;
    return owned < 0 ? 0 : owned;
  }

  Map<String, dynamic> report() => {
        'inner': '$innerWidth x $innerHeight',
        'client': '$clientWidth x $clientHeight',
        'visual': '$visualWidth x $visualHeight offsetTop $visualOffsetTop '
            'scale $visualScale',
        'hostRect': hostRect == null
            ? 'no Flutter host element'
            : 'top ${hostRect!.top} bottom ${hostRect!.bottom} '
                'width ${hostRect!.width} height ${hostRect!.height}',
        'cssInsets': '${cssInsets.top}/${cssInsets.right}/'
            '${cssInsets.bottom}/${cssInsets.left}',
        'overlappedInsets': '${overlappedInsets.top}/${overlappedInsets.right}/'
            '${overlappedInsets.bottom}/${overlappedInsets.left}',
        'viewportMeta': viewportMeta,
        'dpr': devicePixelRatio,
        'rootInlineHeight': rootInlineHeight,
        'rootComputedHeight': rootComputedHeight,
      };
}

/// Read the page: the viewport tag, the window size, Flutter's element, and the
/// safe areas as CSS resolves them.
PageGeometry readPageGeometry() {
  final document = _global('document');
  final meta = _query(document, 'meta[name="viewport"]');
  final host = _query(document, 'flutter-view') ??
      _query(document, 'flt-glass-pane') ??
      _query(document, 'flt-scene-host');
  final root = _child(document, 'documentElement');
  final visual = _child(globalContext, 'visualViewport');

  return PageGeometry(
    cssInsets: _readCssInsets(document),
    hostRect: _readRect(host),
    innerWidth: _num(globalContext, 'innerWidth'),
    innerHeight: _num(globalContext, 'innerHeight'),
    clientWidth: _num(root, 'clientWidth'),
    clientHeight: _num(root, 'clientHeight'),
    rootInlineHeight: _styleValue(root, 'height'),
    rootComputedHeight: _computedHeight(root),
    visualWidth: _num(visual, 'width'),
    visualHeight: _num(visual, 'height'),
    visualOffsetTop: _num(visual, 'offsetTop'),
    visualScale: _num(visual, 'scale'),
    viewportMeta: _str(meta, 'content'),
    devicePixelRatio: _num(globalContext, 'devicePixelRatio'),
  );
}

/// `env(safe-area-inset-*)` only resolves as a *computed* value on a real
/// element in the page, which is why this has to add a probe and read its
/// padding back rather than ask for the values directly.
EdgeInsets _readCssInsets(JSObject document) {
  final body = document['body'];
  if (body == null || !body.isA<JSObject>()) return EdgeInsets.zero;
  final bodyElement = body as JSObject;

  final probe = document.callMethod<JSObject>('createElement'.toJS, 'div'.toJS);
  final style = probe['style'];
  if (style == null || !style.isA<JSObject>()) return EdgeInsets.zero;
  (style as JSObject)['cssText'] =
      ('position:fixed;top:0;left:0;width:0;height:0;'
              'visibility:hidden;pointer-events:none;'
              'padding-top:env(safe-area-inset-top);'
              'padding-right:env(safe-area-inset-right);'
              'padding-bottom:env(safe-area-inset-bottom);'
              'padding-left:env(safe-area-inset-left);')
          .toJS;

  bodyElement.callMethod<JSAny?>('appendChild'.toJS, probe);
  final computed =
      globalContext.callMethod<JSAny?>('getComputedStyle'.toJS, probe);
  final insets = EdgeInsets.only(
    top: _pixels(computed, 'paddingTop'),
    right: _pixels(computed, 'paddingRight'),
    bottom: _pixels(computed, 'paddingBottom'),
    left: _pixels(computed, 'paddingLeft'),
  );
  bodyElement.callMethod<JSAny?>('removeChild'.toJS, probe);
  return insets;
}

Rect? _readRect(JSObject? element) {
  if (element == null) return null;
  final value = element.callMethod<JSAny?>('getBoundingClientRect'.toJS);
  if (value == null || !value.isA<JSObject>()) return null;
  final box = value as JSObject;
  return Rect.fromLTRB(
    _num(box, 'left'),
    _num(box, 'top'),
    _num(box, 'right'),
    _num(box, 'bottom'),
  );
}

/// The root element's own inline `height`, as written by whoever set it - empty
/// when nothing did. Read off `style`, not computed, because "did our code run"
/// is a different question from "what did the browser end up doing".
String _styleValue(JSObject? element, String property) {
  if (element == null) return '';
  final style = element['style'];
  if (style == null || !style.isA<JSObject>()) return '';
  final value = (style as JSObject)[property];
  return value != null && value.isA<JSString>()
      ? (value as JSString).toDart
      : '';
}

/// The height the browser actually resolved for an element.
double _computedHeight(JSObject? element) {
  if (element == null) return -1;
  final style = globalContext.callMethod<JSAny?>(
      'getComputedStyle'.toJS, element as JSAny);
  return _pixels(style, 'height');
}

double _pixels(JSAny? style, String property) {
  if (style == null || !style.isA<JSObject>()) return 0;
  final value = (style as JSObject)[property];
  if (!value.isA<JSString>()) return 0;
  return double.tryParse(
          (value as JSString).toDart.replaceAll('px', '').trim()) ??
      0;
}

JSObject _global(String property) {
  final value = globalContext[property];
  if (value == null || !value.isA<JSObject>()) {
    throw StateError('no $property on the page');
  }
  return value as JSObject;
}

JSObject? _child(JSObject? owner, String key) {
  if (owner == null) return null;
  final value = owner[key];
  return value != null && value.isA<JSObject>() ? value as JSObject : null;
}

JSObject? _query(JSObject document, String selector) {
  final found =
      document.callMethod<JSAny?>('querySelector'.toJS, selector.toJS);
  return found != null && found.isA<JSObject>() ? found as JSObject : null;
}

double _num(JSObject? owner, String key) {
  if (owner == null) return -1;
  final value = owner[key];
  if (value == null || !value.isA<JSNumber>()) return -1;
  return (value as JSNumber).toDartDouble;
}

String _str(JSObject? owner, String key) {
  if (owner == null) return '';
  final value = owner[key];
  if (value == null || !value.isA<JSString>()) return '';
  return (value as JSString).toDart;
}
