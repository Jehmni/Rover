import 'package:flutter/material.dart';
import '../theme/rover_theme.dart';

/// Centered error dialog — requires explicit dismissal so it cannot be missed.
void showErrorDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: RoverColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      title: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: RoverColors.error, size: 26),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Something went wrong',
              style: RoverText.titleMd(),
            ),
          ),
        ],
      ),
      content: Text(message, style: RoverText.bodyMd(color: RoverColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(
            'OK',
            style: RoverText.titleSm(color: RoverColors.primary),
          ),
        ),
      ],
    ),
  );
}

/// Centered info dialog for non-error notices (e.g. "check your email").
void showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  String buttonLabel = 'OK',
  VoidCallback? onDismiss,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: RoverColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      title: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: RoverColors.primary, size: 26),
          const SizedBox(width: 10),
          Flexible(
            child: Text(title, style: RoverText.titleMd()),
          ),
        ],
      ),
      content: Text(message, style: RoverText.bodyMd(color: RoverColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            onDismiss?.call();
          },
          child: Text(
            buttonLabel,
            style: RoverText.titleSm(color: RoverColors.primary),
          ),
        ),
      ],
    ),
  );
}
