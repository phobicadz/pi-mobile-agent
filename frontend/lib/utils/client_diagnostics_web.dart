import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'browser_viewport_web.dart' show readSafeAreaInsets;

/// The other side of the comparison in `client_diagnostics.dart`: what the
/// browser laid the page out as, and how big the Flutter host element actually
/// is on it.
///
/// `inner`/`client`/`visual` are the viewport the browser resolved after the
/// viewport meta was rewritten, `hostRect` is where Flutter's own element sits,
/// and `cssInsets` are the safe areas the app feeds to `MediaQuery`. When the
/// Flutter view size and these disagree, the app is drawing at one size and the
/// page is hit-testing at another - which is what a gap at the bottom and taps
/// that miss their target look like from the outside.
Map<String, dynamic> browserMetrics() {
  final document = _child(globalContext, 'document');
  final visual = _child(globalContext, 'visualViewport');
  final screen = _child(globalContext, 'screen');
  final root = _child(document, 'documentElement');
  final meta = _query(document, 'meta[name="viewport"]');
  final host = _query(document, 'flutter-view') ??
      _query(document, 'flt-glass-pane') ??
      _query(document, 'flt-scene-host');
  final insets = readSafeAreaInsets();

  return {
    'browser': {
      'inner': '${_num(globalContext, 'innerWidth')}x'
          '${_num(globalContext, 'innerHeight')}',
      'client': '${_num(root, 'clientWidth')}x${_num(root, 'clientHeight')}',
      'visual': visual == null
          ? 'none'
          : '${_num(visual, 'width')}x${_num(visual, 'height')} '
              'offsetTop ${_num(visual, 'offsetTop')} '
              'scale ${_num(visual, 'scale')}',
      'screen': '${_num(screen, 'width')}x${_num(screen, 'height')}',
      'dpr': _num(globalContext, 'devicePixelRatio'),
      'viewportMeta': _str(meta, 'content'),
      'hostRect': _rect(host),
      'cssInsets': '${insets.top}/${insets.right}/${insets.bottom}/${insets.left}',
    },
  };
}

JSObject? _child(JSObject? owner, String key) {
  if (owner == null) return null;
  final value = owner[key];
  return value != null && value.isA<JSObject>() ? value as JSObject : null;
}

JSObject? _query(JSObject? document, String selector) {
  if (document == null) return null;
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

String _rect(JSObject? element) {
  if (element == null) return 'no Flutter host element';
  final rect = element.callMethod<JSAny?>('getBoundingClientRect'.toJS);
  if (rect == null || !rect.isA<JSObject>()) return 'unreadable';
  final box = rect as JSObject;
  return 'top ${_num(box, 'top')} bottom ${_num(box, 'bottom')} '
      'width ${_num(box, 'width')} height ${_num(box, 'height')}';
}
