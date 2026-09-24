import 'package:flutter/material.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/auth/timezones.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';

enum _Mode { signIn, register }

/// Sign in or create an account against the backend.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late String _timezone = guessTimezone();
  var _mode = _Mode.register;
  bool _busy = false, _hidePassword = true;
  ApiException? _error;
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AuthScope.read(context).takeSessionExpired()) {
      _mode = _Mode.signIn;
      _notice = 'Your session ended. Please sign in again.';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = AuthScope.read(context);
    try {
      if (_mode == _Mode.register) {
        await auth.register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          timezone: _timezone,
        );
      } else {
        await auth.signIn(_email.text, _password.text);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final register = _mode == _Mode.register;
    final error = _error;
    final general = error != null &&
            error.fieldMessage('email') == null &&
            error.fieldMessage('password') == null &&
            error.fieldMessage('display_name') == null
        ? error.message
        : null;
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                const SizedBox(height: 8),
                const Row(
                  children: [
                    OmniaMark(),
                    SizedBox(width: 10),
                    Text('omnia', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  register ? 'Create your account' : 'Welcome back',
                  style: TextStyle(fontSize: 29, height: 1.05, fontWeight: FontWeight.w900, color: context.foreground),
                ),
                const SizedBox(height: 6),
                Text(
                  register
                      ? 'Your study, tasks, fitness and sleep in one plan.'
                      : 'Sign in to pick up your plan where you left off.',
                  style: TextStyle(color: context.mutedForeground),
                ),
                const SizedBox(height: 20),
                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(value: _Mode.register, label: Text('Create account')),
                    ButtonSegment(value: _Mode.signIn, label: Text('Sign in')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) => setState(() {
                    _mode = selection.single;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 16),
                if (_notice != null) ...[
                  HardCard(color: yellow, shadowOffset: const Offset(2, 2), child: Text(_notice!)),
                  const SizedBox(height: 14),
                ],
                HardCard(
                  color: paper,
                  child: Form(
                    key: _form,
                    child: Column(
                      children: [
                        if (register) ...[
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.givenName],
                            maxLength: 60,
                            decoration: InputDecoration(
                              labelText: 'What should we call you?',
                              errorText: error?.fieldMessage('display_name'),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Enter your name' : null,
                          ),
                          const SizedBox(height: 8),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: 'Email',
                            errorText: error?.fieldMessage('email'),
                          ),
                          validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            helperText: register ? 'At least 8 characters' : null,
                            errorText: error?.fieldMessage('password'),
                            suffixIcon: IconButton(
                              tooltip: _hidePassword ? 'Show password' : 'Hide password',
                              onPressed: () => setState(() => _hidePassword = !_hidePassword),
                              icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            ),
                          ),
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Enter your password';
                            if (register && v.length < 8) return 'Use at least 8 characters';
                            return null;
                          },
                        ),
                        if (register) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _timezone,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Timezone',
                              helperText: 'Decides when your day starts. You can change it later.',
                            ),
                            items: [
                              for (final zone in commonTimezones)
                                DropdownMenuItem(value: zone, child: Text(zone.replaceAll('_', ' '))),
                            ],
                            onChanged: (value) => setState(() => _timezone = value ?? _timezone),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (general != null) ...[
                  const SizedBox(height: 12),
                  Text(general, style: TextStyle(color: context.colors.error, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 18),
                SolidAction(
                  label: _busy
                      ? 'Please wait…'
                      : register
                      ? 'Create account'
                      : 'Sign in',
                  onTap: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
