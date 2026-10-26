import 'package:flutter/material.dart';

/// A brief confirmation toast.
///
/// A floating, width-limited [SnackBar] rather than a full-width bar: it reads
/// as a confirmation about the thing just tapped instead of app chrome covering
/// the prompt field. Success and failure look different, so a silent failure is
/// not possible.
void showToast(BuildContext context, String message, {bool isError = false}) {
  // Captured before any await: the widget that asked for the toast may be gone
  // by the time the copy finishes.
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final iconColor = isError
      ? theme.colorScheme.error
      : (isDark ? const Color(0xFF9CCC65) : const Color(0xFF2E6B12));

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 380,
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle,
                size: 18, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
}
