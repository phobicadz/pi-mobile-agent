import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/pi_models.dart';

/// Open a chat image at the size the screen actually has.
///
/// Full screen rather than the bounded dialog this used to open: a photo of a
/// whiteboard, a screenshot of an error on another machine, or a generated
/// diagram is only readable at something close to the size of the window it is
/// drawn in, and the thumbnail in the chat is already the small version. Opening
/// one and getting 900×700 of it is a second small version - on a phone the
/// screen is the largest thing available, and on a desktop it is the only place a
/// wide diagram fits without scrolling.
///
/// The backdrop is the dialog's own surface (`Dialog.fullscreen` paints
/// `ColorScheme.surface`), which is the decision `file_viewer.dart` records for a
/// picture: a palette is a set of colours chosen against one background and an
/// image has its own. A fixed black would be the same kind of mistake as drawing
/// a photo on a chat bubble.
///
/// The close control lives inside the dialog: a full-screen dialog covers the
/// modal barrier, so there is no "outside" left to tap. Escape still closes it -
/// that is the barrier's own key handler, which is why [showDialog] is left at
/// its default `barrierDismissible`.
void openChatImage(BuildContext context, PiImage image) {
  showDialog<void>(
    context: context,
    // The surface is meant to reach the edges of the screen; the safe area
    // belongs to the control, not to the picture.
    useSafeArea: false,
    builder: (_) => _ChatImageViewer(image: image),
  );
}

class _ChatImageViewer extends StatelessWidget {
  final PiImage image;

  const _ChatImageViewer({required this.image});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog.fullscreen(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Zoom and pan stay: "fullscreen" is the largest the screen can show,
          // not the size the file was drawn at. A screenshot of a log is read by
          // zooming into it.
          InteractiveViewer(
            maxScale: 6,
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: _picture(theme),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: Material(
                color: theme.colorScheme.scrim.withValues(alpha: 0.54),
                shape: const CircleBorder(),
                child: IconButton(
                  // Named for find.byTooltip, the same reason the attachment
                  // tray's remove button is: an icon alone is not a handle.
                  tooltip: 'Close image',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(Icons.close, color: theme.colorScheme.surface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The picture at the size the dialog has, or the reason it is not there.
  ///
  /// The bytes are the ones Pi stored, so a `FormatException` means the stored
  /// value is not what it claims to be - worth saying rather than an empty
  /// screen with no explanation.
  Widget _picture(ThemeData theme) {
    try {
      return Image.memory(
        base64Decode(image.base64Data),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _couldNotDraw(theme),
      );
    } on FormatException {
      return _couldNotDraw(theme);
    }
  }

  Widget _couldNotDraw(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(image.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'This image could not be drawn - ${image.sizeLabel} of '
              '${image.mimeType} data this browser cannot render.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
