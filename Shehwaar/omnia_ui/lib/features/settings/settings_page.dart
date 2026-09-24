import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/models/user.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/state_views.dart';
import 'package:omnia_ui/features/onboarding/onboarding_page.dart';
import 'package:omnia_ui/core/theme/theme_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.of(context);
    // Only in API mode, where someone is signed in.
    final user = AuthScope.maybeOf(context)?.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (user != null) ...[
            _AccountSection(user: user),
            const SizedBox(height: 24),
          ],
          Semantics(
            header: true,
            child: Text(
              'Appearance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
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

/// Who is signed in, and what they can do with their account.
class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.user});
  final User user;

  /// Runs an account action, reporting a backend refusal (wrong password,
  /// offline…) without leaving the screen.
  static Future<void> _attempt(
    BuildContext context,
    Future<void> Function() action, {
    String? done,
  }) async {
    try {
      await action();
      if (done != null && context.mounted) showDone(context, done);
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
    await _attempt(
      context,
      () => AuthScope.read(context).changePassword(result.$1, result.$2),
      done: 'Password changed. Other devices were signed out.',
    );
  }

  Future<void> _signOutEverywhere(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Sign out everywhere?'),
        content: const Text(
          'Every device, including this one, will need to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Sign out everywhere'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _attempt(context, AuthScope.read(context).signOutEverywhere);
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteDialog(),
    );
    if (password == null || !context.mounted) return;
    await _attempt(
      context,
      () => AuthScope.read(context).deleteAccount(password),
    );
  }

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Account',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 12),
        HardCard(
          color: paper,
          shadowOffset: const Offset(2, 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(user.email),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.password),
          title: const Text('Change password'),
          onTap: () => _changePassword(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.devices_other),
          title: const Text('Sign out everywhere'),
          onTap: () => _signOutEverywhere(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => _attempt(context, AuthScope.read(context).signOut),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.delete_forever_outlined, color: danger),
          title: Text('Delete account', style: TextStyle(color: danger)),
          subtitle: const Text('Permanently removes your account and data'),
          onTap: () => _deleteAccount(context),
        ),
      ],
    );
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

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, (_current.text, _next.text));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your current password'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _next,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'New password',
                helperText: 'At least 8 characters',
              ),
              validator: (value) => value == null || value.length < 8
                  ? 'Use at least 8 characters'
                  : null,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _submit, child: const Text('Change')),
    ],
  );
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog();
  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This permanently deletes your account and everything '
                'OMNIA stores for it. It can’t be undone.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm with your password',
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, _password.text);
            }
          },
          child: Text('Delete forever', style: TextStyle(color: danger)),
        ),
      ],
    );
  }
}
