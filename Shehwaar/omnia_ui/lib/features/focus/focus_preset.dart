/// A focus/break pairing. Built-ins are constants; add more to [builtIns].
class FocusPreset {
  const FocusPreset({
    required this.name,
    required this.focus,
    required this.rest,
  });

  static const standard = FocusPreset(
    name: 'Standard',
    focus: Duration(minutes: 25),
    rest: Duration(minutes: 5),
  );
  static const deep = FocusPreset(
    name: 'Deep focus',
    focus: Duration(minutes: 50),
    rest: Duration(minutes: 10),
  );
  static const builtIns = [standard, deep];

  static const maxFocusMinutes = 180, maxBreakMinutes = 60;

  /// Returns an error message, or null when [text] is valid whole minutes.
  static String? validateMinutes(String? text, {required int max}) {
    final minutes = int.tryParse(text?.trim() ?? '');
    if (minutes == null || minutes < 1 || minutes > max) {
      return 'Enter 1 to $max minutes';
    }
    return null;
  }

  factory FocusPreset.custom({
    required int focusMinutes,
    required int breakMinutes,
  }) {
    if (focusMinutes < 1 || focusMinutes > maxFocusMinutes) {
      throw ArgumentError.value(focusMinutes, 'focusMinutes');
    }
    if (breakMinutes < 1 || breakMinutes > maxBreakMinutes) {
      throw ArgumentError.value(breakMinutes, 'breakMinutes');
    }
    return FocusPreset(
      name: 'Custom',
      focus: Duration(minutes: focusMinutes),
      rest: Duration(minutes: breakMinutes),
    );
  }

  final String name;
  final Duration focus, rest;

  bool get isCustom => !builtIns.contains(this);
  String get label => '${focus.inMinutes} / ${rest.inMinutes}';

  @override
  bool operator ==(Object other) =>
      other is FocusPreset &&
      other.name == name &&
      other.focus == focus &&
      other.rest == rest;

  @override
  int get hashCode => Object.hash(name, focus, rest);
}
