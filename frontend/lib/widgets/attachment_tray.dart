import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/pi_models.dart';

/// The images that will go with the next prompt, and the way to take one out.
///
/// Shown above the field rather than sent straight off because "which photo am
/// I about to attach?" is not answerable from a file picker on a phone, and an
/// image the user did not mean to send is only visible once it is on screen.
/// The dimensions and byte size are shown because those are what the model is
/// being charged for.
class AttachmentTray extends StatelessWidget {
  final List<PiImage> images;
  final void Function(int index) onRemove;

  const AttachmentTray({
    super.key,
    required this.images,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < images.length; index++)
          _attachment(context, images[index], index),
      ],
    );
  }

  Widget _attachment(BuildContext context, PiImage image, int index) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;

    final Widget thumbnail = _drawImage(context, image);

    return SizedBox(
      width: 104,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: thumbnail,
              ),
              const SizedBox(height: 2),
              Text(
                image.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: muted),
              ),
              Text(
                image.width > 0
                    ? '${image.width}×${image.height} · ${image.sizeLabel}'
                    : image.sizeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
          Positioned(
            top: -4,
            right: -4,
            child: Material(
              // The scrim token is the theme's own "dark plate over content"
              // colour at the same 54% wash black54 was.
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
              shape: const CircleBorder(),
              child: IconButton(
                // Named for find.byTooltip in tests: several controls in this app
                // are icon-only, and an icon alone is not a handle.
                tooltip: 'Remove image',
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                // White on the plate is the surface colour the chip sits proud
                // of — tokened so a light scheme keeps the same readable pair.
                icon: Icon(Icons.close, color: Theme.of(context).colorScheme.surface),
                onPressed: () => onRemove(index),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Draw the stored image, or the placeholder that says it could not be drawn.
  Widget _drawImage(BuildContext context, PiImage image) {
    try {
      return Image.memory(
        base64Decode(image.base64Data),
        width: 104,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _blank(context),
      );
    } on FormatException {
      return _blank(context);
    }
  }

  Widget _blank(BuildContext context) {
    return Container(
      width: 104,
      height: 72,
      decoration: BoxDecoration(
        // A placeholder's outline is quiet chrome, which is what outlineVariant
        // is for; grey.shade400 is the same grey in every scheme.
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.image_not_supported_outlined, size: 20),
    );
  }
}
