/// The app's appearance choices - theme and chat text size - kept out of the
/// widget tree so they can be read before the first frame and written back
/// without the app knowing where they live.
///
/// The web build stores them in the browser; the native builds do not keep them -
/// see `appearance_store_native.dart` for why.
library;

export 'appearance_store_native.dart'
    if (dart.library.js_interop) 'appearance_store_web.dart';
