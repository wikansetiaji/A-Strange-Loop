import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static const _primaryLight = Color(0xFFFF2D55);
  static const _primaryDark = Color(0xFFFF6B81);
  static const _secondaryLight = Color(0xFFFFD60A);
  static const _secondaryDark = Color(0xFFFFE045);
  static const _tertiaryLight = Color(0xFF5856D6);
  static const _tertiaryDark = Color(0xFF7B79FF);

  static final _lightScheme = ColorScheme.fromSeed(
    seedColor: _primaryLight,
    brightness: Brightness.light,
  ).copyWith(
    primary: _primaryLight,
    onPrimary: const Color(0xFFFFFFFF),
    primaryContainer: const Color(0xFFFFE5EA),
    onPrimaryContainer: const Color(0xFF4A0010),
    secondary: _secondaryLight,
    onSecondary: const Color(0xFF000000),
    secondaryContainer: const Color(0xFFFFF3B0),
    onSecondaryContainer: const Color(0xFF2B2000),
    tertiary: _tertiaryLight,
    onTertiary: const Color(0xFFFFFFFF),
    tertiaryContainer: const Color(0xFFE8E7FF),
    onTertiaryContainer: const Color(0xFF0D0A3D),
    surface: const Color(0xFFFAFAFA),
    surfaceContainerHighest: const Color(0xFFF2F2F2),
    surfaceContainerHigh: const Color(0xFFF5F5F5),
    surfaceContainer: const Color(0xFFF8F8F8),
    surfaceContainerLow: const Color(0xFFFBFBFB),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF111111),
    onSurfaceVariant: const Color(0xFF444444),
    outline: const Color(0xFFBBBBBB),
    outlineVariant: const Color(0xFFE0E0E0),
    error: const Color(0xFFCC0000),
    onError: const Color(0xFFFFFFFF),
    errorContainer: const Color(0xFFFFE5E5),
    onErrorContainer: const Color(0xFF4A0000),
    shadow: const Color(0xFF000000),
    surfaceTint: _primaryLight,
    scrim: const Color(0xFF000000),
  );

  static final _darkScheme = ColorScheme.fromSeed(
    seedColor: _primaryDark,
    brightness: Brightness.dark,
  ).copyWith(
    primary: _primaryDark,
    onPrimary: const Color(0xFF000000),
    primaryContainer: const Color(0xFF4A1020),
    onPrimaryContainer: const Color(0xFFFFE5EA),
    secondary: _secondaryDark,
    onSecondary: const Color(0xFF000000),
    secondaryContainer: const Color(0xFF3D3000),
    onSecondaryContainer: const Color(0xFFFFF3B0),
    tertiary: _tertiaryDark,
    onTertiary: const Color(0xFF000000),
    tertiaryContainer: const Color(0xFF1A184D),
    onTertiaryContainer: const Color(0xFFE8E7FF),
    surface: const Color(0xFF0D0D0D),
    surfaceContainerHighest: const Color(0xFF1C1C1C),
    surfaceContainerHigh: const Color(0xFF161616),
    surfaceContainer: const Color(0xFF121212),
    surfaceContainerLow: const Color(0xFF0F0F0F),
    surfaceContainerLowest: const Color(0xFF080808),
    onSurface: const Color(0xFFEEEEEE),
    onSurfaceVariant: const Color(0xFFBBBBBB),
    outline: const Color(0xFF555555),
    outlineVariant: const Color(0xFF333333),
    error: const Color(0xFFFF6B6B),
    onError: const Color(0xFF000000),
    errorContainer: const Color(0xFF4A0000),
    onErrorContainer: const Color(0xFFFFE5E5),
    shadow: const Color(0xFF000000),
    surfaceTint: _primaryDark,
    scrim: const Color(0xFF000000),
  );

  static TextTheme _buildTextTheme(ColorScheme cs) {
    final space = GoogleFonts.spaceGroteskTextTheme();
    final syne = GoogleFonts.syneTextTheme();

    return space.copyWith(
      displayLarge: syne.displayLarge?.copyWith(color: cs.onSurface),
      displayMedium: syne.displayMedium?.copyWith(color: cs.onSurface),
      displaySmall: syne.displaySmall?.copyWith(color: cs.onSurface),
      headlineLarge: syne.headlineLarge?.copyWith(color: cs.onSurface),
      headlineMedium: syne.headlineMedium?.copyWith(color: cs.onSurface),
      headlineSmall: syne.headlineSmall?.copyWith(color: cs.onSurface),
      titleLarge: syne.titleLarge?.copyWith(color: cs.onSurface),
      titleMedium: space.titleMedium?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: space.titleSmall?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: space.bodyLarge?.copyWith(color: cs.onSurface),
      bodyMedium: space.bodyMedium?.copyWith(color: cs.onSurface),
      bodySmall: space.bodySmall?.copyWith(
        color: cs.onSurface.withAlpha(180),
      ),
      labelLarge: space.labelLarge?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: space.labelMedium?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: space.labelSmall?.copyWith(
        color: cs.onSurface.withAlpha(150),
        letterSpacing: 0.6,
      ),
    );
  }

  static ThemeData light() {
    return _base(_lightScheme);
  }

  static ThemeData dark() {
    return _base(_darkScheme);
  }

  static ThemeData _base(ColorScheme cs) {
    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      textTheme: _buildTextTheme(cs),
      scaffoldBackgroundColor: cs.surface,
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
          side: BorderSide(color: cs.outline, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(0),
          borderSide: BorderSide(color: cs.outline, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(0),
          borderSide: BorderSide(color: cs.outline, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(0),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(color: cs.onSurface.withAlpha(100)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(0),
          ),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(0),
          ),
          side: BorderSide(color: cs.outline, width: 1.5),
        ),
      ),
    );
  }
}

class AppTextStyles {
  AppTextStyles._();

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!;

  static TextStyle display(BuildContext context) =>
      Theme.of(context).textTheme.headlineLarge!;

  static TextStyle appTitle(BuildContext context) =>
      Theme.of(context).textTheme.displaySmall!.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          );

  static TextStyle chatBody(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
            fontSize: 15,
            height: 1.6,
          );

  static TextStyle chatCaption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11);

  static TextStyle sectionLabel(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(90),
          );

  static TextStyle sidebarTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall!.copyWith(
            fontWeight: FontWeight.w700,
          );

  static TextStyle sidebarSubtitle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 12);

  static TextStyle sidebarDate(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10);

  static TextStyle inputHint(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
          );
}
