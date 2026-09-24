import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/features/insights/domain/progress.dart';
import 'package:omnia_ui/features/plan/data/plan_repository.dart';
import 'package:omnia_ui/features/plan/domain/daily_plan.dart';
import 'package:omnia_ui/features/study/domain/study_plan.dart';
import 'package:omnia_ui/features/tasks/data/api_task_repository.dart';
import 'package:omnia_ui/features/tasks/domain/task.dart';

class TodaySummary {
  const TodaySummary({
    required this.studyMinutes,
    required this.studyGoalMinutes,
    required this.tasksCompleted,
    required this.taskGoal,
    required this.steps,
    required this.stepGoal,
    required this.workoutDone,
    required this.workoutMinutes,
    required this.sleepMinutes,
    required this.sleepGoalMinutes,
    required this.calories,
    required this.calorieGoal,
  });

  final int studyMinutes, studyGoalMinutes, tasksCompleted, taskGoal;
  final int steps, stepGoal, workoutMinutes, sleepGoalMinutes, calories, calorieGoal;
  final int? sleepMinutes;
  final bool workoutDone;

  factory TodaySummary.fromJson(Map<String, dynamic> json) => TodaySummary(
    studyMinutes: json['study_minutes'] as int,
    studyGoalMinutes: json['study_goal_minutes'] as int,
    tasksCompleted: json['tasks_completed'] as int,
    taskGoal: json['task_goal'] as int,
    steps: json['steps'] as int,
    stepGoal: json['step_goal'] as int,
    workoutDone: json['workout_status'] == 'done',
    workoutMinutes: json['workout_minutes'] as int? ?? 0,
    sleepMinutes: json['sleep_minutes'] as int?,
    sleepGoalMinutes: json['sleep_goal_minutes'] as int? ?? 480,
    calories: json['calories'] as int? ?? 0,
    calorieGoal: json['calorie_goal'] as int? ?? 2000,
  );
}

class NextExam {
  const NextExam({
    required this.title,
    required this.subjectName,
    required this.date,
    required this.daysLeft,
  });
  final String title, subjectName;
  final DateTime date;
  final int daysLeft;
}

/// Everything the Home screen shows, from one GET /api/dashboard call.
class Dashboard {
  const Dashboard({
    required this.date,
    required this.greeting,
    required this.displayName,
    required this.today,
    required this.streaks,
    required this.nextExam,
    required this.upcomingTasks,
    required this.studyToday,
    required this.plan,
  });

  final DateTime date;
  final String greeting, displayName;
  final TodaySummary today;
  final Streaks streaks;
  final NextExam? nextExam;
  final List<Task> upcomingTasks;
  final List<StudyBlock> studyToday;
  final DailyPlan? plan;

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    final exam = json['next_exam'] == null ? null : asMap(json['next_exam']);
    return Dashboard(
      date: parseDay(json['date'] as String),
      greeting: json['greeting'] as String,
      displayName: json['display_name'] as String,
      today: TodaySummary.fromJson(asMap(json['today'])),
      streaks: Streaks.fromJson(asMap(json['streaks'])),
      nextExam: exam == null
          ? null
          : NextExam(
              title: exam['title'] as String,
              subjectName: exam['subject_name'] as String,
              date: parseDay(exam['exam_date'] as String),
              daysLeft: exam['days_left'] as int,
            ),
      upcomingTasks: [for (final t in asMapList(json['upcoming_tasks'])) taskFromApi(t)],
      studyToday: [for (final b in asMapList(json['study_today'])) StudyBlock.fromJson(b)],
      plan: json['ai_plan'] == null ? null : dailyPlanFromApi(asMap(json['ai_plan'])),
    );
  }
}
