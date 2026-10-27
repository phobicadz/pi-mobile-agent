import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

/// The page geometry the layout has to respect, read from the browser.
///
/// Two different things live here and the app needs both of them: the safe areas
/// the browser reports (`env(safe-area-inset-*)`), and where Flutter's own
/// element actually sits on the page. Comparing the two is the only way to tell
/// which safe areas the app has to reserve for itself and which the browser has
/// already reserved for it - see [PageGeometry.overlappedInsets].
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

  /// The viewport tag in force, which is what decides whether the page is asked
  /// to draw under the safe areas at all.
  final String viewportMeta;

  final double devicePixelRatio;

  /// The part of each safe area that falls inside Flutter's element.
  ///
  /// The app asks the browser to let it draw under the safe areas, and a browser
  /// does not always: an installed iOS app measured here was laid out *below* its
  /// status bar - the Flutter element starting at y=47 with a 47px inset reported
  /// - even with `viewport-fit=cover` in the viewport tag. Reserving the reported
  /// inset in that case is the same space twice, and the app bar sits 47px below
  /// a status bar that was already clear of it.
  ///
  /// Only the overlap is the app's to reserve. Where the browser already kept an
  /// area out of the canvas, adding it again just moves content further from the
  /// edge it was trying to stay away from.
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

double _pixels(JSAny? style, String property) {
  if (style == null || !style.isA<JSObject>()) return 0;
  final value = (style as JSObject)[property];
  if (!value.isA<JSString>()) return 0;
  return double.tryParse((value as JSString).toDart.replaceAll('px', '').trim()) ?? 0;
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
  final found = document.callMethod<JSAny?>('querySelector'.toJS, selector.toJS);
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
