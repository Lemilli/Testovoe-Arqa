import 'package:flutter/material.dart';

/// The sRGB equivalents of the handoff's OKLch palette.
abstract final class ShiftColors {
  static const background = Color(0xFFF4F7F8);
  static const surface = Color(0xFFFFFFFF);
  static const foreground = Color(0xFF172C32);
  static const muted = Color(0xFF4B5B60);
  static const border = Color(0xFFD4DCDF);
  static const accent = Color(0xFF004857);
  static const accentHover = Color(0xFF003745);
  static const hero = Color(0xFF062F3A);
  static const heroInk = Color(0xFFE1EEF1);
  static const soft = Color(0xFFE4EFF3);
  static const error = Color(0xFF862721);
  static const errorBackground = Color(0xFFFFF1EF);
  static const success = Color(0xFF004B2B);
}

ThemeData buildShiftTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: ShiftColors.accent,
    onPrimary: ShiftColors.surface,
    primaryContainer: ShiftColors.soft,
    onPrimaryContainer: ShiftColors.foreground,
    secondary: ShiftColors.foreground,
    onSecondary: ShiftColors.surface,
    secondaryContainer: ShiftColors.soft,
    onSecondaryContainer: ShiftColors.foreground,
    error: ShiftColors.error,
    onError: ShiftColors.surface,
    errorContainer: ShiftColors.errorBackground,
    onErrorContainer: ShiftColors.error,
    surface: ShiftColors.surface,
    onSurface: ShiftColors.foreground,
    onSurfaceVariant: ShiftColors.muted,
    surfaceContainerLowest: ShiftColors.surface,
    surfaceContainerLow: ShiftColors.background,
    surfaceContainer: ShiftColors.background,
    surfaceContainerHigh: ShiftColors.soft,
    surfaceContainerHighest: ShiftColors.border,
    outline: ShiftColors.border,
    outlineVariant: ShiftColors.border,
    inverseSurface: ShiftColors.hero,
    onInverseSurface: ShiftColors.surface,
    inversePrimary: ShiftColors.heroInk,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: ShiftColors.background,
    textTheme: base.textTheme.apply(
      bodyColor: ShiftColors.foreground,
      displayColor: ShiftColors.foreground,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ShiftColors.background,
      foregroundColor: ShiftColors.foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: ShiftColors.foreground,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -.5,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 56)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return ShiftColors.border;
          }
          if (states.contains(WidgetState.pressed)) {
            return ShiftColors.hero;
          }
          if (states.contains(WidgetState.hovered)) {
            return ShiftColors.accentHover;
          }
          return ShiftColors.accent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? ShiftColors.muted
              : ShiftColors.surface,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: ShiftColors.foreground,
        side: const BorderSide(color: ShiftColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: ShiftColors.foreground,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: const TextStyle(color: ShiftColors.muted),
      helperStyle: const TextStyle(color: ShiftColors.muted),
      errorStyle: const TextStyle(color: ShiftColors.error),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ShiftColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ShiftColors.accent, width: 2),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: ShiftColors.border,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ShiftColors.hero,
      contentTextStyle: const TextStyle(color: ShiftColors.surface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: ShiftColors.accent,
      selectionColor: ShiftColors.accent.withValues(alpha: .2),
      selectionHandleColor: ShiftColors.accent,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ShiftColors.accent,
    ),
  );
}
