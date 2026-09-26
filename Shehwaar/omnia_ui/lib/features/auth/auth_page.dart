import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/select_field.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/core/auth/auth_controller.dart';
import 'package:omnia_ui/core/auth/timezones.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/hard_card.dart';
import 'package:omnia_ui/core/widgets/omnia_mark.dart';
import 'package:omnia_ui/core/widgets/solid_action.dart';

/// Sign in, or create an account, against the backend.
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
  var _register = true;
  bool _busy = false, _hidePassword = true;
  ApiException? _error;
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AuthScope.read(context).takeSessionExpired()) {
      _register = false;
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
      if (_register) {
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

  void _switchMode() => setState(() {
    _register = !_register;
    _error = null;
    _notice = null;
  });

  @override
  Widget build(BuildContext context) {
    final error = _error;
    // Field problems show under their field; anything else goes below.
    final general =
        error != null &&
            [
              'email',
              'password',
              'display_name',
              'timezone',
            ].every((field) => error.fieldMessage(field) == null)
        ? error.message
        : null;
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    const Row(
                      children: [
                        OmniaMark(),
                        SizedBox(width: 9),
                        Text(
                          'omnia',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Semantics(
                      header: true,
                      child: Text(
                        _register ? 'Create your account' : 'Welcome back',
                        style: TextStyle(
                          fontSize: 29,
                          height: 1.04,
                          fontWeight: FontWeight.w900,
                          color: context.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _register
                          ? 'Your study, tasks, fitness and sleep in one plan.'
                          : 'Sign in to pick up your plan where you left off.',
                      style: TextStyle(color: context.mutedForeground),
                    ),
                    if (_notice != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: HardCard(
                          color: yellow,
                          shadowOffset: const Offset(2, 3),
                          child: Text(_notice!),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        maxLength: 60,
                        decoration: InputDecoration(
                          labelText: 'Your name',
                          errorText: error?.fieldMessage('display_name'),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your name'
                            : null,
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
                      validator: (value) =>
                          value == null || !value.trim().contains('@')
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      autofillHints: [
                        _register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: _register ? 'At least 8 characters' : null,
                        errorText: error?.fieldMessage('password'),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter your password';
                        }
                        if (_register && value.length < 8) {
                          return 'Use at least 8 characters';
                        }
                        return null;
                      },
                    ),
                    if (_register) ...[
                      const SizedBox(height: 12),
                      SelectField<String>(
                        label: 'Time zone',
                        initialValue: _timezone,
                        helperText: 'Decides when your day starts.',
                        errorText: error?.fieldMessage('timezone'),
                        searchable: true,
                        options: [
                          for (final zone in commonTimezones)
                            SelectOption(zone, zone.replaceAll('_', ' ')),
                        ],
                        onChanged: (value) => setState(() => _timezone = value),
                      ),
                    ],
                    if (general != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          general,
                          style: TextStyle(
                            color: context.colors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SolidAction(
                      label: _busy
                          ? 'Please wait…'
                          : _register
                          ? 'Create account'
                          : 'Sign in',
                      onTap: _submit,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : _switchMode,
                      child: Text(
                        _register
                            ? 'Already have an account? Sign in'
                            : 'New to OMNIA? Create an account',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
