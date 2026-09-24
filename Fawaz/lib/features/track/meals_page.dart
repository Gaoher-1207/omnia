import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/format.dart';
import 'package:omnia_ui/core/session.dart';
import 'package:omnia_ui/core/state/loadable.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/track/domain/wellbeing.dart';

String _label(MealType type) => type.name[0].toUpperCase() + type.name.substring(1);

/// Today's meals: log by hand, or snap a photo and confirm the estimate.
class MealsPage extends StatefulWidget {
  const MealsPage({super.key});
  @override
  State<MealsPage> createState() => _MealsPageState();
}

class _MealsPageState extends State<MealsPage> {
  late final deps = AppDependenciesScope.of(context);
  late final meals = Loadable<DayMeals>(() => deps.track.meals())..load();
  bool _changed = false, _estimating = false;

  @override
  void dispose() {
    meals.dispose();
    super.dispose();
  }

  Future<void> _add({PhotoEstimate? estimate}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AppDependenciesScope(dependencies: deps, child: _MealForm(estimate: estimate)),
    );
    if (saved == true) {
      _changed = true;
      await meals.load();
    }
  }

  Future<void> _fromPhoto() async {
    final picker = ImagePicker();
    final canUseCamera = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    final source = canUseCamera
        ? await showModalBottomSheet<ImageSource>(
            context: context,
            showDragHandle: true,
            builder: (sheet) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('Take a photo'),
                    onTap: () => Navigator.pop(sheet, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Choose from gallery'),
                    onTap: () => Navigator.pop(sheet, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          )
        : ImageSource.gallery;
    if (source == null) return;
    XFile? file;
    try {
      file = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    } catch (_) {
      if (mounted) showDone(context, "Couldn't open the camera or photos on this device.");
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _estimating = true);
    try {
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final type = file.mimeType ??
          (name.endsWith('.png')
              ? 'image/png'
              : name.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg');
      final estimate = await deps.track.estimateFromPhoto(bytes, mediaType: type);
      if (mounted) await _add(estimate: estimate);
    } on ApiException catch (error) {
      if (!mounted) return;
      showDone(
        context,
        error.isUnavailable ? 'Photo analysis isn’t set up on this server. Log the meal by hand.' : error.message,
      );
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _delete(Meal meal) async {
    try {
      await deps.track.deleteMeal(meal.id);
      _changed = true;
      await meals.load();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop && _changed) SessionScope.refreshDashboard(context);
    },
    child: Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(title: const Text('Food', style: TextStyle(fontWeight: FontWeight.w900))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(),
        backgroundColor: context.actionBackground,
        foregroundColor: context.actionForeground,
        icon: const Icon(Icons.add),
        label: const Text('Add meal', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: meals,
          builder: (context, _) {
            final day = meals.data;
            if (day == null) {
              return meals.error == null ? const LoadingView() : ErrorView(error: meals.error!, onRetry: meals.load);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
              children: [
                HardCard(
                  color: yellow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${thousands(day.calories)} kcal',
                        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                      ),
                      Text('of ${thousands(day.calorieGoal)} kcal goal today'),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: ratio(day.calories, day.calorieGoal),
                          minHeight: 8,
                          backgroundColor: context.progressTrack(yellow),
                          color: context.cardForeground(yellow),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SolidAction(
                  label: _estimating ? 'Estimating from photo…' : 'Estimate from a photo',
                  onTap: _estimating ? () {} : _fromPhoto,
                ),
                const SizedBox(height: 18),
                if (day.meals.isEmpty)
                  const MessageView(title: 'No meals logged today', detail: 'Add what you eat to see your totals.')
                else
                  for (final meal in day.meals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: HardCard(
                        shadowOffset: const Offset(2, 3),
                        color: paper,
                        child: Row(
                          children: [
                            const Icon(Icons.restaurant_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(meal.description, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text(
                                    '${_label(meal.type)} · ${meal.calories} kcal · P ${meal.proteinG}g · '
                                    'C ${meal.carbsG}g · F ${meal.fatG}g${meal.fromPhoto ? ' · from photo' : ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete meal',
                              onPressed: () => _delete(meal),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _MealForm extends StatefulWidget {
  const _MealForm({this.estimate});
  final PhotoEstimate? estimate;
  @override
  State<_MealForm> createState() => _MealFormState();
}

class _MealFormState extends State<_MealForm> {
  final _form = GlobalKey<FormState>();
  late final _description = TextEditingController(text: widget.estimate?.description);
  late final _calories = TextEditingController(text: widget.estimate?.calories.toString());
  late final _protein = TextEditingController(text: widget.estimate?.proteinG.toString());
  late final _carbs = TextEditingController(text: widget.estimate?.carbsG.toString());
  late final _fat = TextEditingController(text: widget.estimate?.fatG.toString());
  MealType _type = _guessType();
  bool _saving = false;

  static MealType _guessType() {
    final hour = DateTime.now().hour;
    if (hour < 11) return MealType.breakfast;
    if (hour < 16) return MealType.lunch;
    if (hour < 21) return MealType.dinner;
    return MealType.snack;
  }

  @override
  void dispose() {
    for (final c in [_description, _calories, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AppDependenciesScope.of(context).track.addMeal(
        type: _type,
        description: _description.text,
        calories: _n(_calories),
        proteinG: _n(_protein),
        carbsG: _n(_carbs),
        fatG: _n(_fat),
        fromPhoto: widget.estimate != null,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, error);
      }
    }
  }

  Widget _number(TextEditingController c, String label, int max) => Expanded(
    child: TextFormField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        final n = int.tryParse(v?.trim() ?? '0') ?? -1;
        return (v ?? '').trim().isNotEmpty && (n < 0 || n > max) ? '0–$max' : null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final estimate = widget.estimate;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              estimate == null ? 'Add a meal' : 'Check the estimate',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            if (estimate != null) ...[
              const SizedBox(height: 6),
              Text('Confidence: ${estimate.confidence}. ${estimate.disclaimer}',
                  style: TextStyle(color: context.mutedForeground, fontSize: 12)),
              for (final item in estimate.items) Text('• $item', style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 12),
            SegmentedButton<MealType>(
              segments: [
                for (final type in MealType.values) ButtonSegment(value: type, label: Text(_label(type))),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _type = s.single),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'What did you eat?'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Describe the meal' : null,
            ),
            Row(
              children: [
                _number(_calories, 'kcal', 5000),
                const SizedBox(width: 8),
                _number(_protein, 'Protein g', 500),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _number(_carbs, 'Carbs g', 1000),
                const SizedBox(width: 8),
                _number(_fat, 'Fat g', 500),
              ],
            ),
            const SizedBox(height: 16),
            SolidAction(label: _saving ? 'Saving…' : 'Save meal', onTap: _save),
          ],
        ),
      ),
    );
  }
}
