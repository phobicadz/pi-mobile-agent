import 'image_picking.dart';

/// Non-web builds have no picker wired up.
///
/// Rather than pull in a plugin for a platform this app does not currently ship,
/// the absence is reported honestly and the app hides the control instead of
/// showing one that cannot work.
bool get deviceImagePickerSupported => false;

Future<List<PickedImage>> pickImagesFromDevice() async =>
    throw UnsupportedError('This build has no device image picker.');
