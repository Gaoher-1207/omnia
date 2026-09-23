import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';

ThemeData buildAppTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: paper,
  colorScheme: ColorScheme.fromSeed(
    seedColor: purple,
    brightness: Brightness.light,
  ),
);
