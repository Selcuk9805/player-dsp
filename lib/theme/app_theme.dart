import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dark-first palette. Auravibe doesn't ship a light theme yet — the whole
/// design (album-art-driven color, automix badge states) was built against
/// a dark canvas first.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0A0A0F);
  static const surface = Color(0xFF15151D);
  static const surfaceRaised = Color(0xFF1D1D28);
  static const surfaceBorder = Color(0xFF2A2A38);

  static const textPrimary = Color(0xFFF5F5F9);
  static const textSecondary = Color(0xFF9A9AAD);
  static const textDisabled = Color(0xFF56566A);

  static const accent = Color(0xFF9D7BFF);
  static const accentSecondary = Color(0xFF34D9C4);

  // Automix badge state colors.
  static const automixRed = Color(0xFFFF5C6C);
  static const automixYellow = Color(0xFFFFC24B);
  static const automixGreen = Color(0xFF4FE0A0);
}

class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  static const radiusSm = 10.0;
  static const radiusMd = 16.0;
  static const radiusLg = 24.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    // Two-font pairing, like most real music apps go for: a geometric,
    // slightly heavier display face for titles/headlines (Manrope) paired
    // with a plainer workhorse for body/labels (Inter) — a single font used
    // everywhere at different weights is a big part of what makes an app
    // read as generic/default.
    final baseTextTheme = GoogleFonts.interTextTheme(base.textTheme);
    final displayTextTheme = GoogleFonts.manropeTextTheme(base.textTheme);
    final textTheme = baseTextTheme
        .copyWith(
          displayLarge: displayTextTheme.displayLarge,
          displayMedium: displayTextTheme.displayMedium,
          displaySmall: displayTextTheme.displaySmall,
          headlineLarge: displayTextTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          headlineMedium: displayTextTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          headlineSmall: displayTextTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          titleLarge: displayTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleMedium: displayTextTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        )
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.surface,
        primary: AppColors.accent,
        secondary: AppColors.accentSecondary,
        error: AppColors.automixRed,
      ),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surfaceRaised,
        side: BorderSide.none,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.surfaceBorder,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accent.withValues(alpha: 0.15),
        trackHeight: 3,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: AppColors.accent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.textSecondary,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}
