import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// `visibilitychange` fires whenever the page's visibility state changes, in
/// both directions. Only the way *back* to the foreground matters here, so the
/// handler reads `document.hidden` and acts when it is false.
///
/// The listener is installed on `window` rather than the Flutter canvas: the
/// event is about the page, not the element, and the page is what the browser
/// froze. See `page_foreground.dart` for why the app wants this at all.
void onPageForeground(void Function() cb) {
  final handler = (JSAny? _) {
    final document = globalContext.getProperty<JSObject>('document'.toJS);
    final hidden = document.getProperty<JSAny?>('hidden'.toJS);
    if (hidden.isA<JSBoolean>() && (hidden as JSBoolean).toDart) return;
    cb();
  }.toJS;
  globalContext.callMethod<JSAny?>(
      'addEventListener'.toJS, 'visibilitychange'.toJS, handler);
}
