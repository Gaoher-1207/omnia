enum WorkoutTime { morning, afternoon, evening }

class Profile {
  const Profile({
    required this.displayName,
    required this.timezone,
    required this.studyGoalMinutes,
    required this.stepGoal,
    required this.taskGoal,
    required this.workoutTime,
    required this.sleepGoalMinutes,
    required this.calorieGoal,
    this.username,
  });

  final String displayName, timezone;
  final String? username;
  final int studyGoalMinutes, stepGoal, taskGoal, sleepGoalMinutes, calorieGoal;
  final WorkoutTime workoutTime;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    displayName: json['display_name'] as String,
    timezone: json['timezone'] as String,
    studyGoalMinutes: json['daily_study_goal_minutes'] as int,
    stepGoal: json['daily_step_goal'] as int,
    taskGoal: json['daily_task_goal'] as int,
    workoutTime: WorkoutTime.values.byName(
      json['preferred_workout_time'] as String? ?? 'evening',
    ),
    sleepGoalMinutes: json['daily_sleep_goal_minutes'] as int? ?? 480,
    calorieGoal: json['daily_calorie_goal'] as int? ?? 2000,
    username: json['username'] as String?,
  );
}

class User {
  const User({required this.id, required this.email, required this.profile});
  final String id, email;
  final Profile profile;

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    email: json['email'] as String,
    profile: Profile.fromJson(Map<String, dynamic>.from(json['profile'] as Map)),
  );

  User withProfile(Profile profile) =>
      User(id: id, email: email, profile: profile);
}

/// Small JSON helpers shared by API repositories.
Map<String, dynamic> asMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

List<Map<String, dynamic>> asMapList(dynamic value) =>
    [for (final item in value as List) Map<String, dynamic>.from(item as Map)];

/// Backend dates are `YYYY-MM-DD` in the user's timezone; keep them as local
/// calendar dates (midnight) on the device.
DateTime parseDay(String value) {
  final parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String formatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
