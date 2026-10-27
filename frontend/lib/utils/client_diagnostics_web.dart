import 'dom_geometry_web.dart';

/// The other side of the comparison in `client_diagnostics.dart`: what the page
/// looks like from outside Flutter - the viewport the browser resolved after the
/// viewport meta was rewritten, where Flutter's own element sits on it, the safe
/// areas as CSS reports them, and which of those the app is being asked to
/// reserve.
///
/// When `flutter` in the sample and `browser.overlappedInsets` here disagree about
/// the size or the edges, the app is drawing and hit-testing at one size while
/// the page is laid out at another - which is what a gap at the bottom of the
/// screen and taps that miss their target look like from the outside.
Map<String, dynamic> browserMetrics() {
  final geometry = readPageGeometry();
  return {
    'browser': {
      ...geometry.report(),
      // The visible part of the page minus the part of Flutter's element that is
      // inside it: how much of the canvas is off screen, which on iOS is what the
      // keyboard takes away.
      'canvasOffScreenBottom': geometry.hostRect == null
          ? 0
          : (geometry.hostRect!.bottom -
                  (geometry.visualOffsetTop + geometry.visualHeight))
              .clamp(0, double.maxFinite),
    },
  };
}
