/// Native platforms have no page visibility to watch - the reconnect timer in
/// `PiService` is the whole story there. See `page_foreground.dart`.
void onPageForeground(void Function() cb) {}
