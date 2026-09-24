import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:omnia_ui/features/onboarding/onboarding_page.dart';
import 'package:omnia_ui/core/theme/theme_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Appearance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Theme.of(context).colorScheme.surface,
              ),
            ),
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {controller.value},
            onSelectionChanged: (selection) =>
                controller.value = selection.single,
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (previewContext) => OnboardingPage(
                    onSkip: () => Navigator.pop(previewContext),
                  ),
                ),
              ),
              icon: const Icon(Icons.replay),
              label: const Text('Preview onboarding'),
            ),
          ],
        ],
      ),
    );
  }
}
