/// Native builds do not remember the notification choice.
///
/// Same reason as the appearance settings (see `appearance_store_native.dart`):
/// there is nowhere to put it without another dependency, and a half-working
/// persistence feature reads worse than none. The web build - which is what a
/// phone actually runs this app from - keeps it properly.
library;

Future<bool?> loadNotificationsEnabled() async => null;

void saveNotificationsEnabled(bool enabled) {}
