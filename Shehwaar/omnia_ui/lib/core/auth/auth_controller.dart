import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/core/models/user.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Who is signed in. Restores the saved token at start-up, and drops back to
/// signed-out whenever the backend says the token is no longer valid.
class AuthController extends ChangeNotifier {
  AuthController(this._api) {
    _subscription = _api.onUnauthorized.listen((_) {
      // Only the first rejection of a live session counts; later 401s from
      // requests already in flight find nobody signed in and are ignored.
      if (_user == null) return;
      _user = null;
      _status = AuthStatus.signedOut;
      _sessionExpired = true;
      _notify();
    });
  }

  final ApiClient _api;
  late final StreamSubscription<void> _subscription;
  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  ApiException? _restoreError;
  bool _sessionExpired = false, _disposed = false;

  AuthStatus get status => _status;
  User? get user => _user;

  /// Set when start-up couldn't reach the backend with a saved session.
  ApiException? get restoreError => _restoreError;

  /// True once, after a session expired; the sign-in screen explains it.
  bool takeSessionExpired() {
    final value = _sessionExpired;
    _sessionExpired = false;
    return value;
  }

  Future<void> restore() async {
    _restoreError = null;
    _status = AuthStatus.unknown;
    _notify();
    await _api.restoreToken();
    if (!_api.hasToken) {
      _status = AuthStatus.signedOut;
      _notify();
      return;
    }
    try {
      _user = User.fromJson(asMap(await _api.get('/auth/me')));
      _status = AuthStatus.signedIn;
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        _status = AuthStatus.signedOut;
      } else {
        _restoreError = error; // offline: keep the token, offer a retry
      }
    }
    _notify();
  }

  Future<void> signIn(String email, String password) async => _accept(
    await _api.post(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    ),
  );

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String timezone,
  }) async => _accept(
    await _api.post(
      '/auth/register',
      body: {
        'display_name': name.trim(),
        'email': email.trim(),
        'password': password,
        'timezone': timezone,
      },
    ),
  );

  /// Signs out other devices; this one continues with the new token.
  Future<void> changePassword(String current, String next) async => _accept(
    await _api.post(
      '/auth/change-password',
      body: {'current_password': current, 'new_password': next},
    ),
  );

  /// Sends [changes] (only the fields that changed) to `PATCH /profile` and
  /// keeps the profile the server returns. The account and its session stay
  /// the same. Throws [ApiException] on a refusal.
  Future<void> updateProfile(Map<String, Object?> changes) async {
    if (changes.isEmpty) return;
    final profile = Profile.fromJson(
      asMap(await _api.patch('/profile', body: changes)),
    );
    final user = _user;
    if (user == null) return; // signed out while the request was in flight
    _user = user.withProfile(profile);
    _notify();
  }

  Future<void> _accept(dynamic response) async {
    final data = asMap(response);
    await _api.setToken(data['access_token'] as String);
    _user = User.fromJson(asMap(data['user']));
    _status = AuthStatus.signedIn;
    _notify();
  }

  Future<void> signOut() async {
    await _api.setToken(null);
    _user = null;
    _status = AuthStatus.signedOut;
    _notify();
  }

  Future<void> signOutEverywhere() async {
    await _api.post('/auth/logout-all');
    await signOut();
  }

  Future<void> deleteAccount(String password) async {
    await _api.post('/auth/delete-account', body: {'password': password});
    await signOut();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}

class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({
    super.key,
    required AuthController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthController of(BuildContext context) => maybeOf(context)!;

  /// Null in mock mode, where there is no sign-in.
  static AuthController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()?.notifier;

  /// Read without subscribing (for callbacks).
  static AuthController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AuthScope>()!.notifier!;
}
