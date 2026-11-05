import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'image_picking.dart';

/// The device's own picker, reached the way a browser reaches it: an
/// `<input type="file">`.
///
/// That is the whole reason this feature works on a phone at all - Safari
/// answers a file input with the photo library and the camera, and a desktop
/// browser answers it with the disk, without the app having to know which.
///
/// Written with the same dynamic JS interop the app's other browser helpers
/// use (`appearance_store_web.dart`, `clipboard_web.dart`) rather than
/// `package:web`, which would mean changing the packages this app is built
/// with for one control.
bool get deviceImagePickerSupported => true;

/// A ceiling on walking a browser's file list, not a limit the user sees.
const int _listingBound = 64;

JSObject? _object(String name) {
  final value = globalContext[name];
  return value != null && value.isA<JSObject>() ? value as JSObject : null;
}

Future<List<PickedImage>> pickImagesFromDevice() async {
  final document = _object('document');
  if (document == null) return const [];

  final input =
      document.callMethod<JSObject>('createElement'.toJS, 'input'.toJS);
  input['type'] = 'file'.toJS;
  input['accept'] = 'image/*'.toJS;
  input['multiple'] = true.toJS;
  // Not in the tab order: the control exists only long enough to answer.
  final style = input['style'];
  if (style != null && style.isA<JSObject>()) {
    (style as JSObject)['display'] = 'none'.toJS;
  }

  final body = document['body'];
  if (body != null && body.isA<JSObject>()) {
    (body as JSObject).callMethod<JSAny?>('appendChild'.toJS, input);
  }

  final completer = Completer<List<PickedImage>>();

  void settle(List<PickedImage> images) {
    input.callMethod<JSAny?>('remove'.toJS);
    if (!completer.isCompleted) completer.complete(images);
  }

  void fail(Object error) {
    input.callMethod<JSAny?>('remove'.toJS);
    if (!completer.isCompleted) completer.completeError(error);
  }

  void onChange(JSAny? _) {
    () async {
      try {
        settle(await _readSelectedFiles(input));
      } catch (error) {
        fail(error);
      }
    }();
  }

  // A picker the user closes without choosing fires `cancel` in browsers that
  // implement it and nothing at all in the ones that do not, which is why the
  // caller also puts a timeout on this.
  void onCancel(JSAny? _) => settle(const []);

  input.callMethod<JSAny?>(
      'addEventListener'.toJS, 'change'.toJS, onChange.toJS);
  input.callMethod<JSAny?>(
      'addEventListener'.toJS, 'cancel'.toJS, onCancel.toJS);
  input.callMethod<JSAny?>('click'.toJS);

  return completer.future;
}

Future<List<PickedImage>> _readSelectedFiles(JSObject input) async {
  final filesValue = input['files'];
  if (filesValue == null || !filesValue.isA<JSObject>()) return const [];
  final files = filesValue as JSObject;

  final picked = <PickedImage>[];
  // `item()` returns nothing past the end of the list, which is a simpler and
  // more honest end than reading `length` and converting a JS number. The bound
  // is only there so a browser that misbehaves cannot keep this loop running;
  // the limit the user is told about is enforced in the view model.
  for (var index = 0; index < _listingBound; index++) {
    final fileValue = files.callMethod<JSAny?>('item'.toJS, index.toJS);
    if (fileValue == null || !fileValue.isA<JSObject>()) break;
    final file = fileValue as JSObject;

    final nameValue = file['name'];
    final name = nameValue != null && nameValue.isA<JSString>()
        ? (nameValue as JSString).toDart
        : 'image';

    picked.add(PickedImage(name: name, bytes: await _readFileBytes(file)));
  }
  return picked;
}

/// `file.arrayBuffer()`, awaited.
///
/// The alternative is `FileReader`, which is older, callback-shaped code. This
/// is available in every browser this app is realistically opened in.
Future<Uint8List> _readFileBytes(JSObject file) async {
  final promise = file.callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS);
  final buffer = await promise.toDart;
  return buffer.toDart.asUint8List();
}
