import 'package:flutter/material.dart';

/// Centered error dialog — requires explicit dismissal so it cannot be missed.
void showErrorDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      title: const Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red, size: 26),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              'Something went wrong',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.black87),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text(
            'OK',
            style: TextStyle(
              color: Color(0xFF478DE0),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      title: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF478DE0), size: 26),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.black87),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            onDismiss?.call();
          },
          child: Text(
            buttonLabel,
            style: const TextStyle(
              color: Color(0xFF478DE0),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ],
    ),
  );
}
