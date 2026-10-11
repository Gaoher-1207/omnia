import 'package:flutter/material.dart';
import 'package:omnia_ui/app.dart';
import 'package:omnia_ui/features/onboarding/onboarding_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read once before the first frame; the native splash covers the wait.
  final onboarding = SecureOnboardingStore();
  final complete = await onboarding.isComplete();
  runApp(OmniaApp(onboardingStore: onboarding, onboardingComplete: complete));
}
