/// Whether the app says so when a run finishes, kept out of the widget tree so
/// the choice can be read back before the first frame and written without the
/// screen knowing where it lives.
///
/// The web build stores it in the browser; the native builds do not - see
/// `notification_store_native.dart` for why.
library;

export 'notification_store_native.dart'
    if (dart.library.js_interop) 'notification_store_web.dart';
