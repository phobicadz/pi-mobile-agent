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
