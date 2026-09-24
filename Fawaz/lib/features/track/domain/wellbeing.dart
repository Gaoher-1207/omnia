import 'package:omnia_ui/core/models/user.dart';

class ActivityDay {
  const ActivityDay({
    required this.day,
    this.steps = 0,
    this.workoutDone = false,
    this.workoutMinutes = 0,
    this.workoutType,
  });
  final DateTime day;
  final int steps, workoutMinutes;
  final bool workoutDone;
  final String? workoutType;

  factory ActivityDay.fromJson(Map<String, dynamic> json) => ActivityDay(
    day: parseDay(json['day'] as String),
    steps: json['steps'] as int? ?? 0,
    workoutDone: json['workout_done'] as bool? ?? false,
    workoutMinutes: json['workout_minutes'] as int? ?? 0,
    workoutType: json['workout_type'] as String?,
  );
}

class SleepEntry {
  const SleepEntry({
    required this.day,
    required this.minutes,
    this.quality,
    this.logged = true,
  });
  final DateTime day;
  final int minutes;
  final int? quality;
  final bool logged;

  factory SleepEntry.fromJson(Map<String, dynamic> json) => SleepEntry(
    day: parseDay(json['day'] as String),
    minutes: json['duration_minutes'] as int? ?? 0,
    quality: json['quality'] as int?,
    logged: json['logged'] as bool? ?? true,
  );
}

enum MealType { breakfast, lunch, dinner, snack }

class Meal {
  const Meal({
    required this.id,
    required this.type,
    required this.description,
    required this.calories,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.fromPhoto = false,
  });
  final String id, description;
  final MealType type;
  final int calories, proteinG, carbsG, fatG;
  final bool fromPhoto;

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
    id: json['id'] as String,
    type: MealType.values.byName(json['meal_type'] as String),
    description: json['description'] as String,
    calories: json['calories'] as int,
    proteinG: json['protein_g'] as int,
    carbsG: json['carbs_g'] as int,
    fatG: json['fat_g'] as int,
    fromPhoto: json['source'] == 'photo_estimate',
  );
}

class DayMeals {
  const DayMeals({required this.day, required this.calorieGoal, required this.meals});
  final DateTime day;
  final int calorieGoal;
  final List<Meal> meals;

  int get calories => meals.fold(0, (sum, meal) => sum + meal.calories);
}

/// Nutrition numbers the backend estimated from a photo; nothing is saved
/// until the user confirms.
class PhotoEstimate {
  const PhotoEstimate({
    required this.description,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.confidence,
    required this.items,
    required this.disclaimer,
  });
  final String description, confidence, disclaimer;
  final int calories, proteinG, carbsG, fatG;
  final List<String> items;

  factory PhotoEstimate.fromJson(Map<String, dynamic> json) {
    final totals = asMap(json['totals']);
    return PhotoEstimate(
      description: json['suggested_description'] as String,
      calories: totals['calories'] as int,
      proteinG: totals['protein_g'] as int,
      carbsG: totals['carbs_g'] as int,
      fatG: totals['fat_g'] as int,
      confidence: json['confidence'] as String,
      disclaimer: json['disclaimer'] as String? ?? '',
      items: [
        for (final item in asMapList(json['items']))
          '${item['name']}${item['portion'] == null ? '' : ' (${item['portion']})'} · ${item['calories']} kcal',
      ],
    );
  }
}
