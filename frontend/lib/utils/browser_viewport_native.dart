import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart' show EdgeInsets;

/// Native platforms already report their safe areas through the platform
/// channel, so there is nothing to bridge and nothing to opt into.
ValueNotifier<EdgeInsets> useBrowserSafeArea() =>
    ValueNotifier<EdgeInsets>(EdgeInsets.zero);
