import 'package:flutter/material.dart';

class AppTheme {
  static const Color _trustBlue = Color(0xFF0369A1);
  static const Color _secondaryBlue = Color(0xFF0EA5E9);
  static const Color _securityGreen = Color(0xFF22C55E);
  static const Color _danger = Color(0xFFB42318);
  static const Color _lightCanvas = Color(0xFFF3F8FC);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightInk = Color(0xFF0B2536);
  static const Color _lightMuted = Color(0xFF526D7D);
  static const Color _lightOutline = Color(0xFFC9DDE8);
  static const Color _darkCanvas = Color(0xFF08151F);
  static const Color _darkSurface = Color(0xFF102331);
  static const Color _darkSurfaceHigh = Color(0xFF173245);
  static const Color _darkInk = Color(0xFFEAF6FC);
  static const Color _darkMuted = Color(0xFFA8BECA);
  static const Color _darkOutline = Color(0xFF29485B);

  static ThemeData light() {
    return _build(
      brightness: Brightness.light,
      canvas: _lightCanvas,
      surface: _lightSurface,
      surfaceHigh: const Color(0xFFE7F3FA),
      ink: _lightInk,
      muted: _lightMuted,
      outline: _lightOutline,
      primary: _trustBlue,
      secondary: _secondaryBlue,
      tertiary: _securityGreen,
      danger: _danger,
    );
  }

  static ThemeData dark() {
    return _build(
      brightness: Brightness.dark,
      canvas: _darkCanvas,
      surface: _darkSurface,
      surfaceHigh: _darkSurfaceHigh,
      ink: _darkInk,
      muted: _darkMuted,
      outline: _darkOutline,
      primary: const Color(0xFF38BDF8),
      secondary: const Color(0xFF7DD3FC),
      tertiary: const Color(0xFF4ADE80),
      danger: const Color(0xFFF97066),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color canvas,
    required Color surface,
    required Color surfaceHigh,
    required Color ink,
    required Color muted,
    required Color outline,
    required Color primary,
    required Color secondary,
    required Color tertiary,
    required Color danger,
  }) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
          primary: primary,
          secondary: secondary,
          surface: surface,
          error: danger,
        ).copyWith(
          primary: primary,
          secondary: secondary,
          tertiary: tertiary,
          surface: surface,
          surfaceContainerHighest: surfaceHigh,
          outline: outline,
          outlineVariant: outline.withValues(alpha: 0.65),
          onSurface: ink,
          onPrimary: Colors.white,
          onSecondary: brightness == Brightness.dark
              ? const Color(0xFF062033)
              : Colors.white,
          onTertiary: brightness == Brightness.dark
              ? const Color(0xFF052E18)
              : Colors.white,
          error: danger,
          onError: Colors.white,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
    );

    final textTheme = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: 0,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: 0,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: 0,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        height: 1.45,
        color: ink,
        letterSpacing: 0,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        height: 1.45,
        color: muted,
        letterSpacing: 0,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        height: 1.35,
        color: muted,
        letterSpacing: 0,
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: muted,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primary : muted,
          );
        }),
      ),
      textTheme: textTheme,
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: outline.withValues(alpha: 0.85)),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        textColor: ink,
        tileColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: surface,
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.78)),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primary, width: 1.3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: danger, width: 1.3),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _buttonStyle()),
      filledButtonTheme: FilledButtonThemeData(style: _buttonStyle()),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: outline),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFFEAF6FC)
            : _lightInk,
        contentTextStyle: TextStyle(
          color: brightness == Brightness.dark ? _darkCanvas : Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static ButtonStyle _buttonStyle() {
    return FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
  }
}
