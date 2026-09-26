import 'package:omnia_ui/core/api/api_client.dart';
import 'package:omnia_ui/core/api/json.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_message.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_repository.dart';

/// Ask Omnia on the backend (`POST /api/ai/chat`). The server builds the
/// signed-in user's context from the token; the body carries only the
/// question and recent turns, never ids, a user or any context.
class ApiAssistantRepository implements AssistantRepository {
  ApiAssistantRepository(this._api);
  final ApiClient _api;

  /// Longer than the server's 60 s model timeout, so its own "took too long"
  /// answer arrives instead of a network error. The first question after the
  /// model has been idle includes loading it.
  static const timeout = Duration(seconds: 75);

  /// The backend's limits: at most 10 earlier turns of 2000 characters.
  static const maxHistory = 10, maxTurnLength = 2000;

  @override
  Future<String> ask(String message, List<AssistantMessage> history) async {
    final recent = history.length > maxHistory
        ? history.sublist(history.length - maxHistory)
        : history;
    final reply = asMap(
      await _api.post(
        '/ai/chat',
        timeout: timeout,
        body: {
          'message': message,
          'history': [
            for (final turn in recent)
              {
                'role': turn.role.name,
                'content': turn.text.length > maxTurnLength
                    ? turn.text.substring(0, maxTurnLength)
                    : turn.text,
              },
          ],
        },
      ),
    );
    return reply['reply'] as String;
  }
}
