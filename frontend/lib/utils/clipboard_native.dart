import 'package:flutter/services.dart';

import 'clipboard.dart';

/// iOS / Android / desktop: the platform channel is the clipboard.
Future<CopyOutcome> copyImpl(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return CopyOutcome.copied;
  } catch (_) {
    return CopyOutcome.failed;
  }
}
