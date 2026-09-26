import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/surface_style.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';

/// The product typeface: titles, body, buttons, values, navigation. The
/// theme applies it everywhere, so widgets never name it.
const archivo = 'Archivo';

/// The utility typeface, for short text only. Use it through [OmniaText].
const spaceMono = 'SpaceMono';

/// The only places Space Mono appears. Never for sentences or body copy.
abstract final class OmniaText {
  /// Small uppercase tags and eyebrow labels: SAMPLE, TODAY, LAST NIGHT.
  static const label = TextStyle(
    fontFamily: spaceMono,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: .8,
    height: 1.3,
  );

  /// Compact metadata: dates, times, counts and targets beside a value.
  static const meta = TextStyle(fontFamily: spaceMono, fontSize: 12);
}

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
  final selectedFill = dark ? sleepDark : lilac;
  HardInputBorder field(BorderSide side) =>
      HardInputBorder(borderSide: side, shadow: surface.shadow);
  // Styles handed to Material components below replace, rather than merge
  // with, the inherited text style, so each names the family itself.
  final bold = TextStyle(
    fontFamily: archivo,
    fontWeight: FontWeight.w800,
    color: scheme.onSurface,
  );
  final theme = ThemeData(
    useMaterial3: true,
    fontFamily: archivo,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    // Filled buttons are always bright fills, so they keep the ink outline.
    filledButtonTheme: FilledButtonThemeData(
      style: buttonStyle.copyWith(
        side: WidgetStatePropertyAll(surface.side.copyWith(color: ink)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: buttonStyle.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? selectedFill
              : scheme.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? ink : scheme.onSurface,
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: archivo, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: dark ? darkSurface : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: surface.side,
      ),
    ),
    // Fields share the cards' language: a hard outline with a solid offset.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? darkSurfaceElevated : paper,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: bold,
      floatingLabelStyle: bold,
      contentPadding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      border: field(surface.side),
      enabledBorder: field(surface.side),
      focusedBorder: field(
        BorderSide(color: dark ? sleepDark : purple, width: 2.4),
      ),
      errorBorder: field(surface.side.copyWith(color: scheme.error)),
      focusedErrorBorder: field(BorderSide(color: scheme.error, width: 2.4)),
      disabledBorder: field(
        surface.side.copyWith(color: surface.outline.withValues(alpha: .4)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? darkSurface : scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: archivo,
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
      ),
      shape: Border(bottom: surface.side),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: surface.side.copyWith(color: surface.outlineOn(selectedFill)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: dark ? darkSurfaceElevated : ink,
      contentTextStyle: TextStyle(
        fontFamily: archivo,
        color: dark ? darkTextPrimary : Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: surface.side,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 0,
      color: dark ? darkSurfaceElevated : paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: surface.side,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      elevation: 0,
      backgroundColor: dark ? darkSurface : paper,
      showDragHandle: true,
      dragHandleColor: surface.outline,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: surface.side,
      ),
    ),
  );
  final text = theme.textTheme;
  // Heavier weights carry the hierarchy for titles and buttons.
  return theme.copyWith(
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

/// An outlined field border that also paints the unblurred offset "shadow"
/// cards use, as a sliver outside the outline so the fill is untouched.
class HardInputBorder extends OutlineInputBorder {
  const HardInputBorder({
    super.borderSide,
    required this.shadow,
    this.offset = const Offset(2, 3),
  }) : super(borderRadius: const BorderRadius.all(Radius.circular(10)));
  final Color shadow;
  final Offset offset;

  @override
  HardInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) => HardInputBorder(
    borderSide: borderSide ?? this.borderSide,
    shadow: shadow,
    offset: offset,
  );

  // Focus changes animate between borders; stay a hard border throughout.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is OutlineInputBorder
      ? copyWith(borderSide: BorderSide.lerp(a.borderSide, borderSide, t))
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is OutlineInputBorder
      ? copyWith(borderSide: BorderSide.lerp(borderSide, b.borderSide, t))
      : super.lerpTo(b, t);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final outer = getOuterPath(rect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer.shift(offset), outer),
      Paint()..color = shadow,
    );
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
  }
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
