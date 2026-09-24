import 'package:flutter/foundation.dart';

/// Where the OMNIA backend lives.
///
/// Set it at build/run time, e.g.
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
///
/// Without it, debug builds use the local development server:
///   Android emulator → http://10.0.2.2:8000/api (the emulator's alias for your computer)
///   everything else  → http://localhost:8000/api
/// Release builds have no default: they must be given API_BASE_URL.
abstract final class ApiConfig {
  static const _fromEnvironment = String.fromEnvironment('API_BASE_URL');

  /// `--dart-define=OMNIA_DATA=api` signs in against the backend. Anything
  /// else (the default) runs on in-memory mock data with no sign-in.
  static const apiMode = String.fromEnvironment('OMNIA_DATA') == 'api';

  /// The base URL to use, or null when a release build wasn't configured.
  /// The parameters default to the running build; tests pass their own.
  static String? resolveBaseUrl({
    String fromEnvironment = _fromEnvironment,
    bool releaseMode = kReleaseMode,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
  }) {
    if (fromEnvironment.isNotEmpty) return _trim(fromEnvironment);
    if (releaseMode) return null;
    final androidEmulator =
        !isWeb && (platform ?? defaultTargetPlatform) == TargetPlatform.android;
    return androidEmulator
        ? 'http://10.0.2.2:8000/api'
        : 'http://localhost:8000/api';
  }

  static String _trim(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
