import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/surface_style.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final baseScheme = ColorScheme.fromSeed(
    seedColor: purple,
    brightness: brightness,
    surface: dark ? night : paper,
    onSurface: dark ? darkTextPrimary : ink,
  );
  final scheme = dark
      ? baseScheme.copyWith(
          surface: darkBackground,
          surfaceDim: darkBackground,
          surfaceBright: darkSurfaceElevated,
          surfaceContainerLowest: darkBackground,
          surfaceContainerLow: darkSurface,
          surfaceContainer: darkSurface,
          surfaceContainerHigh: darkSurfaceElevated,
          surfaceContainerHighest: darkSurfaceElevated,
          onSurfaceVariant: darkTextSecondary,
          primary: sleepDark,
          onPrimary: ink,
          primaryContainer: darkPrimary,
          onPrimaryContainer: darkTextPrimary,
          secondaryContainer: darkSurfaceElevated,
          onSecondaryContainer: darkTextPrimary,
        )
      : baseScheme;
  final surface = SurfaceStyle(brightness);
  final buttonStyle = ButtonStyle(
    elevation: const WidgetStatePropertyAll(0),
    side: WidgetStatePropertyAll(surface.side),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    // Filled buttons are always bright fills, so they keep the ink outline.
    filledButtonTheme: FilledButtonThemeData(
      style: buttonStyle.copyWith(
        side: WidgetStatePropertyAll(surface.side.copyWith(color: ink)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    segmentedButtonTheme: SegmentedButtonThemeData(style: buttonStyle),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: dark ? darkSurface : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: surface.side,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: surface.side,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: surface.side,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? darkSurface : scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
  );
}

/// Semantic surfaces retain the original pastel families in both themes.
extension OmniaTheme on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get navigationSurface => isDark ? darkSurface : colors.surface;
  Color cardForeground(Color accent, {bool prominent = false}) =>
      isDark && prominent
      ? darkTextPrimary
      : isDark &&
            (accent == blue ||
                accent == yellow ||
                accent == mint ||
                accent == lilac)
      ? ink
      : foreground;
  Color progressTrack(Color accent) => isDark
      ? Color.alphaBlend(ink.withValues(alpha: .18), cardColor(accent))
      : colors.surfaceContainerHighest;
  Color get foreground => colors.onSurface;
  Color get mutedForeground => colors.onSurfaceVariant;
  Color get outline => SurfaceStyle.of(this).outline;
  Color outlineOn(Color fill) => SurfaceStyle.of(this).outlineOn(fill);
  Color get actionBackground =>
      Theme.of(this).brightness == Brightness.dark ? sleepDark : ink;
  Color get actionForeground =>
      Theme.of(this).brightness == Brightness.dark ? ink : Colors.white;

  Color cardColor(Color accent, {bool prominent = false}) {
    if (Theme.of(this).brightness != Brightness.dark) return accent;
    if (prominent) return darkPrimary;
    if (accent == paper) return colors.surfaceContainer;
    if (accent == lilac) return sleepDark;
    if (accent == blue) return studyDark;
    if (accent == yellow) return tasksDark;
    if (accent == mint) return activityDark;
    return accent;
  }
}
