import 'dart:async';

import 'clipboard_native.dart'
    if (dart.library.js_interop) 'clipboard_web.dart' as impl;

/// Outcome of a copy attempt. Reported rather than thrown: a copy button has to
/// be able to say what happened, and on the web the browser may refuse.
enum CopyOutcome { copied, failed }

/// Put [text] on the system clipboard.
///
/// Never throws. The web implementation falls back to a DOM copy when the browser
/// has no Clipboard API - see `clipboard_web.dart`, which is the case that
/// matters here: the app is served over plain `http://<lan-ip>:3000`.
Future<CopyOutcome> copyToClipboard(String text) => impl.copyImpl(text);
