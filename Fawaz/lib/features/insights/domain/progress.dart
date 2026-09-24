import 'package:omnia_ui/core/models/user.dart';

class Streak {
  const Streak({required this.current, required this.longest, required this.activeToday});
  final int current, longest;
  final bool activeToday;

  factory Streak.fromJson(Map<String, dynamic> json) => Streak(
    current: json['current'] as int,
    longest: json['longest'] as int,
    activeToday: json['active_today'] as bool,
  );
}

class Streaks {
  const Streaks({
    required this.study,
    required this.tasks,
    required this.fitness,
    required this.balance,
  });
  final Streak study, tasks, fitness, balance;

  factory Streaks.fromJson(Map<String, dynamic> json) => Streaks(
    study: Streak.fromJson(asMap(json['study'])),
    tasks: Streak.fromJson(asMap(json['tasks'])),
    fitness: Streak.fromJson(asMap(json['fitness'])),
    balance: Streak.fromJson(asMap(json['balance'])),
  );
}

class DayProgress {
  const DayProgress({
    required this.date,
    required this.studyMinutes,
    required this.tasksCompleted,
    required this.steps,
    required this.workoutDone,
    required this.balanced,
    this.sleepMinutes,
    this.calories = 0,
  });
  final DateTime date;
  final int studyMinutes, tasksCompleted, steps, calories;
  final int? sleepMinutes;
  final bool workoutDone, balanced;

  factory DayProgress.fromJson(Map<String, dynamic> json) => DayProgress(
    date: parseDay(json['date'] as String),
    studyMinutes: json['study_minutes'] as int,
    tasksCompleted: json['tasks_completed'] as int,
    steps: json['steps'] as int,
    workoutDone: json['workout_done'] as bool,
    balanced: json['balanced'] as bool,
    sleepMinutes: json['sleep_minutes'] as int?,
    calories: json['calories'] as int? ?? 0,
  );
}

class Progress {
  const Progress({required this.date, required this.streaks, required this.history});
  final DateTime date;
  final Streaks streaks;
  final List<DayProgress> history;
}

class Achievement {
  const Achievement({
    required this.code,
    required this.title,
    required this.description,
    required this.earned,
    required this.progress,
    required this.target,
  });
  final String code, title, description;
  final bool earned;
  final int progress, target;

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
    code: json['code'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    earned: json['earned'] as bool,
    progress: json['progress'] as int,
    target: json['target'] as int,
  );
}
