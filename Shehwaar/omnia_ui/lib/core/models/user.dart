/// The signed-in account, from the backend's `UserOut`. Only what the app
/// uses so far; the profile's daily targets arrive with that feature.
class User {
  const User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.timezone,
    this.username,
  });

  final String id, email, displayName, timezone;
  final String? username;

  factory User.fromJson(Map<String, dynamic> json) {
    final profile = Map<String, dynamic>.from(json['profile'] as Map);
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: profile['display_name'] as String,
      timezone: profile['timezone'] as String,
      username: profile['username'] as String?,
    );
  }
}
