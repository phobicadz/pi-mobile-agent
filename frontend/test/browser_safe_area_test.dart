import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/utils/browser_viewport.dart';

void main() {
  test('native platforms report no safe areas to add', () {
    // Tests run on the host, where the native implementation is the one that
    // gets compiled in: iOS and Android tell Flutter their own insets, so there
    // is nothing for the app to bridge.
    expect(useBrowserSafeArea().value, EdgeInsets.zero);
  });

  testWidgets('covered safe areas become insets the layout respects',
      (tester) async {
    final safeArea = ValueNotifier<EdgeInsets>(EdgeInsets.zero);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Pi Agent')),
        // The shape HomeScreen actually uses: the chat takes what is left and
        // the prompt field keeps its own height inside a SafeArea.
        body: Column(
          children: [
            Expanded(child: SizedBox(key: Key('chat'))),
            SafeArea(
              top: false,
              child: SizedBox(key: Key('prompt'), height: 60),
            ),
          ],
        ),
      ),
      builder: (context, child) =>
          applyBrowserSafeArea(context, child, safeArea),
    ));

    final chatBefore = tester.getRect(find.byKey(const Key('chat')));
    final promptBefore = tester.getRect(find.byKey(const Key('prompt')));

    // What the browser reports once the page is allowed to draw under the
    // status bar and the home indicator.
    safeArea.value = const EdgeInsets.only(top: 44, bottom: 34);
    await tester.pump();

    final chatAfter = tester.getRect(find.byKey(const Key('chat')));
    final promptAfter = tester.getRect(find.byKey(const Key('prompt')));

    // The app bar absorbs the top inset, so the chat starts below it rather
    // than under the clock...
    expect(chatAfter.top - chatBefore.top, 44);
    // ...and the prompt field ends above the home indicator instead of under it.
    expect(promptAfter.bottom, promptBefore.bottom - 34);
    // The prompt keeps its own height; the chat gives up what both of them now
    // take - 44 more app bar and 34 more SafeArea under the prompt.
    expect(promptAfter.height, promptBefore.height);
    expect(chatBefore.height - chatAfter.height, 78);

    // The insets reach the screen itself. Inside the body they read as zero
    // afterwards, because a Scaffold consumes them for its own app bar and
    // body - which is exactly what the geometry above shows.
    final media = MediaQuery.of(tester.element(find.byType(Scaffold)));
    expect(media.padding.top, 44);
    expect(media.padding.bottom, 34);
  });

  testWidgets('no reported safe areas leave the layout untouched',
      (tester) async {
    final safeArea = ValueNotifier<EdgeInsets>(EdgeInsets.zero);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Pi Agent')),
        body: const SizedBox(key: Key('body')),
      ),
      builder: (context, child) =>
          applyBrowserSafeArea(context, child, safeArea),
    ));

    final without = tester.getRect(find.byKey(const Key('body')));

    safeArea.value = const EdgeInsets.all(0);
    await tester.pump();

    expect(tester.getRect(find.byKey(const Key('body'))), without);
  });
}
