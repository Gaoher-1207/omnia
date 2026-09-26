import 'package:omnia_ui/features/assistant/domain/assistant_message.dart';

/// Answers questions about the user's day. Read-only: asking never changes
/// any OMNIA data. The API implementation's server gathers the user's
/// context itself; the app sends only the question and recent turns.
abstract interface class AssistantRepository {
  /// Longest question the backend accepts.
  static const maxMessageLength = 1000;

  /// [history] is the conversation so far, oldest first, without [message].
  /// Returns the reply text; failures throw (an `ApiException` in API mode).
  Future<String> ask(String message, List<AssistantMessage> history);
}
