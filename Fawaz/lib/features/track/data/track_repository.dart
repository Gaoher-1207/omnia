import 'dart:convert';
import 'dart:typed_data';

import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';

/// Activity, sleep and meals (`/api/activity`, `/api/sleep`, `/api/meals`).
class TrackRepository {
  TrackRepository(this._api);
  final ApiClient _api;

  Future<List<ActivityDay>> activityRange(DateTime from, DateTime to) async {
    final json = asMap(
      await _api.get('/activity', query: {'from': formatDay(from), 'to': formatDay(to)}),
    );
    return [for (final day in asMapList(json['days'])) ActivityDay.fromJson(day)];
  }

  Future<ActivityDay> activity(DateTime day) async =>
      ActivityDay.fromJson(asMap(await _api.get('/activity/${formatDay(day)}')));

  Future<ActivityDay> saveActivity(
    DateTime day, {
    required int steps,
    required bool workoutDone,
    int workoutMinutes = 0,
    String? workoutType,
  }) async => ActivityDay.fromJson(
    asMap(
      await _api.put(
        '/activity/${formatDay(day)}',
        body: {
          'steps': steps,
          'workout_done': workoutDone,
          'workout_minutes': workoutDone ? workoutMinutes : 0,
          'workout_type': workoutDone && (workoutType ?? '').trim().isNotEmpty
              ? workoutType!.trim()
              : null,
        },
      ),
    ),
  );

  Future<SleepEntry> sleep(DateTime day) async =>
      SleepEntry.fromJson(asMap(await _api.get('/sleep/${formatDay(day)}')));

  Future<SleepEntry> saveSleep(DateTime day, {required int minutes, int? quality}) async =>
      SleepEntry.fromJson(
        asMap(
          await _api.put(
            '/sleep/${formatDay(day)}',
            body: {'duration_minutes': minutes, 'quality': quality},
          ),
        ),
      );

  Future<DayMeals> meals([DateTime? day]) async {
    final json = asMap(
      await _api.get('/meals', query: {'day': day == null ? null : formatDay(day)}),
    );
    return DayMeals(
      day: parseDay(json['day'] as String),
      calorieGoal: json['calorie_goal'] as int,
      meals: [for (final meal in asMapList(json['meals'])) Meal.fromJson(meal)],
    );
  }

  Future<Meal> addMeal({
    required MealType type,
    required String description,
    required int calories,
    int proteinG = 0,
    int carbsG = 0,
    int fatG = 0,
    bool fromPhoto = false,
  }) async => Meal.fromJson(
    asMap(
      await _api.post(
        '/meals',
        body: {
          'meal_type': type.name,
          'description': description.trim(),
          'calories': calories,
          'protein_g': proteinG,
          'carbs_g': carbsG,
          'fat_g': fatG,
          'source': fromPhoto ? 'photo_estimate' : 'manual',
        },
      ),
    ),
  );

  Future<void> deleteMeal(String id) => _api.delete('/meals/$id');

  /// Sends the photo to OMNIA's backend (never straight to an AI provider).
  Future<PhotoEstimate> estimateFromPhoto(
    Uint8List bytes, {
    required String mediaType,
    String? note,
  }) async => PhotoEstimate.fromJson(
    asMap(
      await _api.post(
        '/nutrition/estimate',
        body: {
          'image_base64': base64Encode(bytes),
          'media_type': mediaType,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
        timeout: const Duration(seconds: 60),
      ),
    ),
  );
}
