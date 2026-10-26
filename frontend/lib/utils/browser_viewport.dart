import 'package:flutter/widgets.dart';

import 'browser_viewport_native.dart'
    if (dart.library.js_interop) 'browser_viewport_web.dart' as impl;

/// Ask the browser for the whole screen, and keep its safe areas in step.
///
/// On native platforms this does nothing and reports no insets: iOS and Android
/// already tell Flutter where the notch, status bar and home indicator are.
///
/// On the web the browser owns those areas instead, so this is where the app
/// becomes full height on a phone - see `browser_viewport_web.dart`.
ValueNotifier<EdgeInsets> useBrowserSafeArea() => impl.useBrowserSafeArea();

/// Re-establish the [MediaQuery] that [child] sits under, with the browser's
/// safe areas added to its insets.
///
/// For use as `MaterialApp.builder`, which is the one place an app can wrap the
/// subtree the screens are built in: the insets themselves come from a `View`
/// above the app, so overriding `MediaQuery` from outside the app would be
/// replaced by the app's own. Flutter Web reports these as empty, which is why
/// the app has to add them itself once it has asked the browser to draw under
/// them - otherwise covering the home indicator just buries the prompt field.
Widget applyBrowserSafeArea(
  BuildContext context,
  Widget? child,
  ValueNotifier<EdgeInsets> safeArea,
) {
  return ValueListenableBuilder<EdgeInsets>(
    valueListenable: safeArea,
    builder: (context, insets, _) {
      if (insets == EdgeInsets.zero) return child!;
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          padding: _covered(media.padding, insets),
          viewPadding: _covered(media.viewPadding, insets),
        ),
        child: child!,
      );
    },
  );
}

/// Add the covered areas to an inset set, whatever shape it came in.
///
/// [EdgeInsetsGeometry] only resolves to a concrete [EdgeInsets] against a text
/// direction, and `MediaQueryData` wants the concrete one.
EdgeInsets _covered(EdgeInsetsGeometry base, EdgeInsets insets) {
  final resolved = base.resolve(TextDirection.ltr);
  return EdgeInsets.only(
    top: resolved.top + insets.top,
    right: resolved.right + insets.right,
    bottom: resolved.bottom + insets.bottom,
    left: resolved.left + insets.left,
  );
}
