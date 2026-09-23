import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/surface_style.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: purple,
    brightness: brightness,
    surface: dark ? night : paper,
    onSurface: dark ? const Color(0xFFF1EDF7) : ink,
  );
  final surface = SurfaceStyle(brightness);
  final buttonStyle = ButtonStyle(
    elevation: const WidgetStatePropertyAll(0),
    side: WidgetStatePropertyAll(surface.side),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    segmentedButtonTheme: SegmentedButtonThemeData(style: buttonStyle),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: scheme.surface,
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
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
  );
}

/// Semantic surfaces retain the original pastel families in both themes.
extension OmniaTheme on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  Color get foreground => colors.onSurface;
  Color get mutedForeground => colors.onSurfaceVariant;
  Color get outline => SurfaceStyle.of(this).outline;
  Color get actionBackground =>
      Theme.of(this).brightness == Brightness.dark ? lilac : ink;
  Color get actionForeground =>
      Theme.of(this).brightness == Brightness.dark ? ink : Colors.white;

  Color cardColor(Color accent) {
    if (Theme.of(this).brightness != Brightness.dark) return accent;
    if (accent == paper) return colors.surfaceContainer;
    if (accent == lilac) return const Color(0xFF40334F);
    if (accent == blue) return const Color(0xFF293E58);
    if (accent == yellow) return const Color(0xFF4B4027);
    if (accent == mint) return const Color(0xFF25473D);
    return accent;
  }
}
