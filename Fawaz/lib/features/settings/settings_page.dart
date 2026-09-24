import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/app_dependencies.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/onboarding/onboarding_page.dart';
import 'package:omnia_ui/core/theme/theme_controller.dart';
import 'package:omnia_ui/features/settings/goals_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _heading = TextStyle(fontSize: 20, fontWeight: FontWeight.w900);

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.of(context);
    final auth = AuthScope.of(context);
    final user = auth.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (user != null) ...[
            const Text('Account', style: _heading),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(user.profile.displayName),
              subtitle: Text(
                '${user.email}${user.profile.username == null ? '' : '  ·  @${user.profile.username}'}',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Daily goals, timezone and username'),
              subtitle: Text(
                '${user.profile.studyGoalMinutes ~/ 60}h study · ${user.profile.taskGoal} tasks · '
                '${user.profile.stepGoal} steps · ${user.profile.timezone}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const GoalsPage())),
            ),
            const SizedBox(height: 12),
          ],
          const Text('Appearance', style: _heading),
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
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
            ],
            selected: {controller.value},
            onSelectionChanged: (selection) => controller.value = selection.single,
          ),
          if (user != null) ...[
            const SizedBox(height: 24),
            const Text('Calendar', style: _heading),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Subscribe in Google, Apple or Outlook Calendar'),
              subtitle: const Text('A private link with your tasks, exams and today’s plan'),
              onTap: () => _calendarLink(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link_off),
              title: const Text('Turn off calendar link'),
              onTap: () => _revokeCalendar(context),
            ),
            const SizedBox(height: 12),
            const Text('Your data', style: _heading),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_outlined),
              title: const Text('Copy all my data (JSON)'),
              subtitle: const Text('Everything OMNIA stores about you'),
              onTap: () => _export(context),
            ),
            const SizedBox(height: 12),
            const Text('Security', style: _heading),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.password),
              title: const Text('Change password'),
              onTap: () => _changePassword(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.devices_other),
              title: const Text('Sign out on all devices'),
              onTap: () => _confirm(
                context,
                'Sign out everywhere?',
                'Every device, including this one, will need to sign in again.',
                () => auth.signOutEverywhere(),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => auth.signOut(),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
              title: Text('Delete account', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: const Text('Permanently removes your account and all your data'),
              onTap: () => _deleteAccount(context),
            ),
          ],
          if (kDebugMode) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (previewContext) => OnboardingPage(onSkip: () => Navigator.pop(previewContext)),
                ),
              ),
              icon: const Icon(Icons.replay),
              label: const Text('Preview onboarding'),
            ),
            Text(
              'Server: ${AppDependenciesScope.of(context).api.baseUrl}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _calendarLink(BuildContext context) async {
    try {
      final data = asMap(await AppDependenciesScope.of(context).api.post('/integrations/calendar'));
      final url = data['url'] as String;
      await Clipboard.setData(ClipboardData(text: url));
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Calendar link copied'),
          content: SelectableText(
            '$url\n\nAdd it as a subscribed calendar ("From URL"). Anyone with the link can read '
            'your tasks and plan; making a new link turns the old one off.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Done'))],
        ),
      );
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _revokeCalendar(BuildContext context) async {
    try {
      await AppDependenciesScope.of(context).api.delete('/integrations/calendar');
      if (context.mounted) showDone(context, 'Calendar link turned off.');
    } on ApiException catch (error) {
      if (context.mounted) {
        showDone(context, error.isNotFound ? 'There was no calendar link to turn off.' : error.message);
      }
    }
  }

  Future<void> _export(BuildContext context) async {
    try {
      final data = await AppDependenciesScope.of(context).api.get('/account/export');
      final text = const JsonEncoder.withIndent('  ').convert(data);
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        showDone(context, 'Copied your data (${(text.length / 1024).toStringAsFixed(1)} KB) to the clipboard.');
      }
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _confirm(BuildContext context, String title, String message, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await action();
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      await AuthScope.read(context).changePassword(result.$1, result.$2);
      if (context.mounted) showDone(context, 'Password changed. Other devices were signed out.');
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteDialog(),
    );
    if (password == null || !context.mounted) return;
    try {
      await AuthScope.read(context).deleteAccount(password);
    } on ApiException catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters'),
            validator: (v) => v == null || v.length < 8 ? 'Use at least 8 characters' : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) Navigator.pop(context, (_current.text, _next.text));
        },
        child: const Text('Change'),
      ),
    ],
  );
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog();
  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delete your account?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'This permanently deletes your tasks, study records, activity, sleep, meals, plans, '
          'friends and posts. It can’t be undone.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm with your password'),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(
        onPressed: () {
          if (_password.text.isNotEmpty) Navigator.pop(context, _password.text);
        },
        child: Text('Delete forever', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
    ],
  );
}
