import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the access token lives between app launches.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

/// Keychain (iOS/macOS), Keystore-backed storage (Android), libsecret (Linux),
/// DPAPI (Windows). If the platform store is unavailable, the token is kept in
/// memory only, so the app still works but asks for sign-in after a restart.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'omnia.access_token';
  final FlutterSecureStorage _storage;
  String? _fallback;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key) ?? _fallback;
    } catch (_) {
      return _fallback;
    }
  }

  @override
  Future<void> write(String? token) async {
    _fallback = token;
    try {
      if (token == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: token);
      }
    } catch (_) {
      // Keep the in-memory copy; see class comment.
    }
  }
}

/// For tests and previews.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.token]);
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String? token) async => this.token = token;
}
