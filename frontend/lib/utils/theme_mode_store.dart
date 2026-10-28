/// The light/dark choice, kept out of the widget tree so it can be read before
/// the first frame and written back without the app knowing where it lives.
///
/// The web build stores it in the browser; the native builds do not keep it -
/// see `theme_mode_store_native.dart` for why.
library;

export 'theme_mode_store_native.dart'
    if (dart.library.js_interop) 'theme_mode_store_web.dart';
