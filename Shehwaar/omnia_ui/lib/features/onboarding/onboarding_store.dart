import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether this device has finished (or skipped) the first-run intro. It is
/// a device preference, not account data: switching accounts never shows the
/// intro again.
abstract interface class OnboardingStore {
  Future<bool> isComplete();
  Future<void> markComplete();
}

/// Persists completion in the platform secure store the token already uses.
/// Failures never block the app: an unreadable store means "show the intro",
/// and a failed write only means the intro may appear once more.
class SecureOnboardingStore implements OnboardingStore {
  SecureOnboardingStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'omnia.onboarding_complete';
  final FlutterSecureStorage _storage;

  @override
  Future<bool> isComplete() async {
    try {
      return await _storage
              .read(key: _key)
              .timeout(const Duration(seconds: 2)) ==
          'true';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> markComplete() async {
    try {
      await _storage.write(key: _key, value: 'true');
    } catch (_) {
      // See class comment.
    }
  }
}

/// For tests, previews and mock-mode runs that should not persist anything.
class MemoryOnboardingStore implements OnboardingStore {
  MemoryOnboardingStore([this.complete = false]);
  bool complete;
  int writes = 0;

  @override
  Future<bool> isComplete() async => complete;

  @override
  Future<void> markComplete() async {
    writes++;
    complete = true;
  }
}
