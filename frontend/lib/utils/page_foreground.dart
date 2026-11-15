import 'page_foreground_native.dart'
    if (dart.library.js_interop) 'page_foreground_web.dart' as impl;

/// Run [cb] each time this page comes back to the foreground.
///
/// A phone browser does not keep a backgrounded (or screen-off) page alive in
/// the same way it keeps a visible one: the page is frozen and its websockets
/// drop with it. The reconnect timer alone cannot make that instant - a frozen
/// page does not run timers while it is away, and the app only learns the
/// socket is gone when the user is already standing there waiting. This hook
/// lets the app re-establish the socket at the moment it becomes visible
/// again, which is the moment the user returns to it.
///
/// On native platforms this does nothing: the process is not frozen this way
/// and the reconnect timer already covers a dropped socket.
void onPageForeground(void Function() cb) => impl.onPageForeground(cb);
