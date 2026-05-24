import 'package:flutter/material.dart';

enum SnackBarType { info, success, error, warning, undo }

class SnackBarHelper {
  static final Map<SnackBarType, Color> _colors = {
    SnackBarType.info: const Color(0xFF1C1C1C),
    SnackBarType.success: const Color(0xFF1C1C1C),
    SnackBarType.error: const Color(0xFF8B0000),
    SnackBarType.warning: const Color(0xFF5C3D00),
    SnackBarType.undo: const Color(0xFF1C1C1C),
  };

  static final Map<SnackBarType, Duration> _durations = {
    SnackBarType.info: const Duration(seconds: 2),
    SnackBarType.success: const Duration(seconds: 2),
    SnackBarType.error: const Duration(seconds: 3),
    SnackBarType.warning: const Duration(seconds: 3),
    SnackBarType.undo: const Duration(seconds: 5),
  };

  static void show(
    BuildContext context, {
    required String message,
    SnackBarType type = SnackBarType.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: _colors[type],
        duration: _durations[type]!,
        behavior: SnackBarBehavior.fixed,
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: type == SnackBarType.undo
                    ? const Color(0xFF6B8AFF)
                    : Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }
}
