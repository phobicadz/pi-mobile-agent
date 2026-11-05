import 'dart:typed_data';

import 'image_picking_native.dart'
    if (dart.library.js_interop) 'image_picking_web.dart' as impl;

/// One image the user chose on the device, before any of the decisions about
/// size and type are made - those belong to `image_attachment.dart`, which is
/// testable and does not depend on a browser.
class PickedImage {
  final String name;
  final Uint8List bytes;

  const PickedImage({required this.name, required this.bytes});
}

/// Whether this build can open the device's own file picker.
///
/// The web build can (an `<input type="file">`, which is how a phone's Safari
/// offers the photo library and a desktop browser offers the disk). A build
/// compiled for iOS or Android cannot, and says so rather than showing a button
/// that does nothing.
bool get deviceImagePickerSupported => impl.deviceImagePickerSupported;

/// Ask the device for images. Resolves to an empty list when the user closes
/// the picker without choosing anything.
Future<List<PickedImage>> pickImagesFromDevice() => impl.pickImagesFromDevice();
