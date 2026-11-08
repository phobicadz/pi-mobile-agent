import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Open the menu the app bar's hamburger operates, and let it finish opening.
///
/// The controls live in that menu now, so a test that presses one has to ask
/// for it first - exactly what a person on the phone does.
///
/// The pump loop instead of `pumpAndSettle` because the drawer animates while
/// the chat behind it may be animating too, and a settle that never arrives is
/// a timeout that says nothing about the thing being tested.
Future<void> openAppMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The menu row that offers [icon].
///
/// A row with nothing to do is a row that is switched off, so tests can read
/// `onTap == null` as the control being closed rather than missing.
Finder menuRow(IconData icon) =>
    find.ancestor(of: find.byIcon(icon), matching: find.byType(ListTile));

/// Scroll the menu until [target] is on screen.
///
/// The menu is a list, and a test window is not a phone tall enough to show all
/// of it at once; tapping a row that is below the fold taps whatever is at that
/// point on the screen instead, which is a silent way to test nothing.
Future<void> scrollMenuIntoView(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: find
        .descendant(of: find.byType(Drawer), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pump();
}

/// Tap a menu row and let the sheet it opens appear.
Future<void> tapMenuRow(WidgetTester tester, IconData icon) async {
  final row = menuRow(icon);
  await scrollMenuIntoView(tester, row);
  await tester.tap(row);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The switch in the menu row whose title is exactly [title].
///
/// The menu has more than one switch now - the notice and the chat's compact
/// view - so `find.byType(Switch)` is not a control, it is whichever row the
/// menu happened to build first, and a tap on it presses the wrong setting.
/// A row's title is what a person reads to know which switch they are about to
/// move, so it is what the test reads too.
///
/// [title] is the state-dependent wording these rows use, which means the caller
/// names the state it expects to find - and a row that failed to change when it
/// was pressed fails to be found at all, which is the right way to fail.
Finder menuSwitch(String title) => find.descendant(
    of: find.widgetWithText(ListTile, title), matching: find.byType(Switch));

/// Open the file browser from the folder in the app bar.
///
/// The menu used to be the way in. It is not any more: the bar says which
/// directory this is, so it is the thing that changes it, and tests that need
/// the browser should reach it the way a person does now - without opening a
/// menu first.
Future<void> openFileBrowser(WidgetTester tester) async {
  final folder = find.descendant(
    of: find.byType(AppBar),
    matching: find.byIcon(Icons.folder_open),
  );
  await tester.tap(folder);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Open the session picker from the centre of the app bar.
///
/// The centre of the bar is the conversation: its name when it has one (pass
/// [sessionName] to press that), and the sessions icon when it has none (leave
/// it out). The menu used to be the way in and no longer is, so a test reaches
/// it the way a person does - from the conversation it is about to replace.
Future<void> openSessionPicker(
  WidgetTester tester, {
  String? sessionName,
}) async {
  final target = find.descendant(
    of: find.byType(AppBar),
    matching: sessionName == null
        ? find.byIcon(Icons.forum_outlined)
        : find.text(sessionName),
  );
  await tester.tap(target);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
