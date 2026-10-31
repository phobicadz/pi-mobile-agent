import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';

import 'clipboard.dart';

/// Browser copy.
///
/// `navigator.clipboard` only exists in a secure context - https, or localhost.
/// The engine turns the missing API into a `copy_fail` PlatformException, so on
/// a plain `http://192.168.2.1:3000` home-LAN deployment every copy would fail.
/// The DOM fallback below works in either context, which is why it is a fallback
/// rather than the first attempt: the Clipboard API is the modern path and this
/// is only the safety net.
///
/// `web/index.html` installs the same safety net as `navigator.clipboard` itself
/// when the browser has none, because a text selection's Copy is issued by the
/// engine and nothing in this app is in that path. That is why the first attempt
/// below normally succeeds on a plain-http page: the fallback here is what a
/// browser that refuses to copy at all lands on.
Future<CopyOutcome> copyImpl(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return CopyOutcome.copied;
  } on PlatformException {
    return _copyThroughDom(text) ? CopyOutcome.copied : CopyOutcome.failed;
  } catch (_) {
    return CopyOutcome.failed;
  }
}

/// `document.execCommand('copy')` on a throwaway textarea: old, deprecated, and
/// still the only thing that copies in an insecure context. Called from inside
/// the tap handler, where the browser still counts it as a user action.
bool _copyThroughDom(String text) {
  try {
    final document = globalContext['document'];
    if (document == null || !document.isA<JSObject>()) return false;
    final doc = document as JSObject;
    final body = doc['body'];
    if (body == null || !body.isA<JSObject>()) return false;
    final bodyElement = body as JSObject;

    final textarea =
        doc.callMethod<JSObject>('createElement'.toJS, 'textarea'.toJS);
    textarea['value'] = text.toJS;
    final style = textarea['style'];
    if (style != null && style.isA<JSObject>()) {
      final css = style as JSObject;
      // On-screen but invisible: a display:none element has no selection to
      // copy, and an unpositioned one scrolls the page to reach it.
      css['position'] = 'fixed'.toJS;
      css['top'] = '0'.toJS;
      css['left'] = '0'.toJS;
      css['opacity'] = '0'.toJS;
    }

    bodyElement.callMethod<JSAny?>('appendChild'.toJS, textarea);
    textarea.callMethod<JSAny?>('select'.toJS);
    final copied = doc.callMethod<JSAny?>('execCommand'.toJS, 'copy'.toJS);
    bodyElement.callMethod<JSAny?>('removeChild'.toJS, textarea);

    return copied == true.toJS;
  } catch (_) {
    return false;
  }
}
