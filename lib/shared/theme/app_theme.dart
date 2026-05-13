import 'package:flutter/material.dart';

class AppTheme {
  static const Color _trustBlue = Color(0xFF0B63CE);
  static const Color _securityGreen = Color(0xFF1F8F5F);
  static const Color _canvas = Color(0xFFF4F7FB);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF142033);
  static const Color _muted = Color(0xFF60708A);
  static const Color _outline = Color(0xFFD6DFEA);

  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _trustBlue,
          brightness: Brightness.light,
          primary: _trustBlue,
          secondary: _securityGreen,
          surface: _surface,
        ).copyWith(
          primary: _trustBlue,
          secondary: _securityGreen,
          surface: _surface,
          surfaceContainerHighest: const Color(0xFFEAF0F7),
          outline: _outline,
          outlineVariant: const Color(0xFFE1E7F0),
          onSurface: _ink,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _canvas,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: _canvas,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: _ink,
        ),
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: _ink,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          height: 1.45,
          color: _ink,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          height: 1.45,
          color: _muted,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: colorScheme.surface,
        labelStyle: const TextStyle(color: _muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _trustBlue, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFB3261E)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: _outline,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
