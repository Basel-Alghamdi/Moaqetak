import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF3B82F6);
  static const Color surface = Color(0xFF151922);
  static const Color surfaceAlt = Color(0xFF1B2130);
  static const Color bg = Color(0xFF0F1115);
  static const Color border = Color(0xFF2A3243);
  static const Color danger = Color(0xFF7F1D1D);
  static const Color success = Color(0xFF166534);
}

class AppButtons {
  static ButtonStyle primary() => ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  static ButtonStyle secondary() => ElevatedButton.styleFrom(
        backgroundColor: AppColors.surfaceAlt,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
      );

  static ButtonStyle outline() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );
}

class AppBanner extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;

  const AppBanner.error(this.message, {super.key})
      : color = AppColors.danger,
        icon = Icons.error_outline;

  const AppBanner.info(this.message, {super.key})
      : color = AppColors.surfaceAlt,
        icon = Icons.info_outline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class AppTag extends StatelessWidget {
  final String text;
  final Color? bg;
  final Color? fg;
  final IconData? icon;
  final EdgeInsets padding;

  const AppTag(
    this.text, {
    super.key,
    this.bg,
    this.fg,
    this.icon,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final colorBg = bg ?? AppColors.surfaceAlt;
    final colorFg = fg ?? Colors.white70;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colorBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colorFg),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(color: colorFg, fontSize: 12)),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool success = false}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: success ? AppColors.success : Colors.black87,
      content: Text(message, textDirection: TextDirection.rtl),
      duration: const Duration(seconds: 2),
    ),
  );
}
