import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart' show Color, EdgeInsets;

/// Native platforms already report their safe areas through the platform
/// channel, so there is nothing to bridge and nothing to opt into.
ValueNotifier<EdgeInsets> useBrowserSafeArea() =>
    ValueNotifier<EdgeInsets>(EdgeInsets.zero);

/// Nor is there a page behind the canvas to paint: on these platforms the canvas
/// is the screen.
void paintPageBehindCanvas(Color colour) {}
