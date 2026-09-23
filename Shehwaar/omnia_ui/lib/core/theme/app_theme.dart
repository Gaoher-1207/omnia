import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: purple,
    brightness: brightness,
    surface: dark ? night : paper,
    onSurface: dark ? const Color(0xFFF1EDF7) : ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
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
  Color get outline => Theme.of(this).brightness == Brightness.dark
      ? const Color(0xFFAAA1BC)
      : ink;
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
