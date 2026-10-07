import 'package:flutter/material.dart';

/// University brand colour (deep magenta), also used on the website.
const brandColor = Color(0xFF910051);
const brandDark = Color(0xFF5E0034);
const brandLight = Color(0xFFF7E6EF);

/// Light and dark Material 3 themes with one typeface for Kurdish, Arabic and Latin.
class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: brandColor,
      brightness: brightness,
      primary: dark ? const Color(0xFFFFAFD0) : brandColor,
      surface: dark ? const Color(0xFF151218) : const Color(0xFFFAF7F9),
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Vazirmatn');
    final text = base.textTheme.apply(fontFamily: 'Vazirmatn');

    return base.copyWith(
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.5),
      ),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF1F1B22) : Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.4 : 0.6)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF1F1B22) : Colors.white,
        indicatorColor: scheme.primary.withValues(alpha: dark ? 0.25 : 0.12),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF26222A) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w600, fontSize: 13),
          visualDensity: VisualDensity.compact,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF1F1B22) : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

/// Gradient used behind headers (home, login, profile).
LinearGradient brandGradient(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: dark ? const [Color(0xFF5E0034), Color(0xFF2A1420)] : const [brandColor, Color(0xFFB8296F)],
  );
}
