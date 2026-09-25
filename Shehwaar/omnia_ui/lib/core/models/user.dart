/// The signed-in account, from the backend's `UserOut`.
class User {
  const User({required this.id, required this.email, required this.profile});

  final String id, email;
  final Profile profile;

  String get displayName => profile.displayName;
  String get timezone => profile.timezone;
  String? get username => profile.username;

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    email: json['email'] as String,
    profile: Profile.fromJson(
      Map<String, dynamic>.from(json['profile'] as Map),
    ),
  );

  /// The same account with a profile the server just returned.
  User withProfile(Profile profile) =>
      User(id: id, email: email, profile: profile);
}

enum WorkoutTime { morning, afternoon, evening }

/// The backend's `ProfileOut`: who the user is, plus their **daily targets**.
/// Daily targets are the day-by-day numbers Home and Track measure against;
/// they are not the long-term Goals feature. A target of 0 means "not
/// tracking".
class Profile {
  const Profile({
    required this.displayName,
    required this.timezone,
    required this.studyGoalMinutes,
    required this.stepGoal,
    required this.taskGoal,
    required this.sleepGoalMinutes,
    required this.calorieGoal,
    required this.workoutTime,
    this.username,
  });

  final String displayName;

  /// IANA name; decides when the user's day starts.
  final String timezone;

  /// Lowercase handle for friends, if set.
  final String? username;
  final int studyGoalMinutes, stepGoal, taskGoal, sleepGoalMinutes;
  final int calorieGoal;
  final WorkoutTime workoutTime;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    displayName: json['display_name'] as String,
    timezone: json['timezone'] as String,
    username: json['username'] as String?,
    studyGoalMinutes: json['daily_study_goal_minutes'] as int,
    stepGoal: json['daily_step_goal'] as int,
    taskGoal: json['daily_task_goal'] as int,
    sleepGoalMinutes: json['daily_sleep_goal_minutes'] as int,
    calorieGoal: json['daily_calorie_goal'] as int,
    workoutTime: WorkoutTime.values.byName(
      json['preferred_workout_time'] as String,
    ),
  );

  Map<String, Object?> toJson() => {
    'display_name': displayName,
    'timezone': timezone,
    'username': username,
    'daily_study_goal_minutes': studyGoalMinutes,
    'daily_step_goal': stepGoal,
    'daily_task_goal': taskGoal,
    'daily_sleep_goal_minutes': sleepGoalMinutes,
    'daily_calorie_goal': calorieGoal,
    'preferred_workout_time': workoutTime.name,
  };

  /// The `PATCH /profile` body that turns [before] into this profile: only
  /// the fields that differ.
  Map<String, Object?> changesSince(Profile before) {
    final old = before.toJson();
    return {
      for (final MapEntry(:key, :value) in toJson().entries)
        if (old[key] != value) key: value,
    };
  }
}
