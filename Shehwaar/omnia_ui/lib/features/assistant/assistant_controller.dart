import 'package:flutter/widgets.dart';
import 'package:omnia_ui/core/api/api_exception.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_message.dart';
import 'package:omnia_ui/features/assistant/domain/assistant_repository.dart';

/// Why the last question went unanswered, so the page can say so plainly.
enum AssistantFailure {
  /// The server answered 503: the assistant is off, offline or has no model.
  unavailable,

  /// The request never got an answer: no connection, or it timed out.
  network,
  other,
}

/// One user's Ask Omnia conversation. It lives in the signed-in session and
/// is never stored, so signing out (or in as someone else) starts afresh.
class AssistantController extends ChangeNotifier {
  AssistantController(this._repository);
  final AssistantRepository _repository;

  List<AssistantMessage> _messages = const [];
  String? _pending;
  bool _sending = false, _disposed = false;
  Object? _error;

  /// Answered turns, oldest first.
  List<AssistantMessage> get messages => _messages;

  /// The question being answered, or the one that failed and can be retried.
  String? get pending => _pending;
  bool get sending => _sending;
  Object? get error => _error;

  AssistantFailure? get failure => switch (_error) {
    null => null,
    ApiException(isUnavailable: true) => AssistantFailure.unavailable,
    ApiException(isNetwork: true) => AssistantFailure.network,
    _ => AssistantFailure.other,
  };

  bool get isEmpty => _messages.isEmpty && _pending == null;

  /// Asks [text]. Ignored while another question is in flight; a question
  /// that failed is replaced by the new one.
  Future<void> send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _sending) return;
    _pending = question;
    await _ask();
  }

  /// Asks the failed question again.
  Future<void> retry() async {
    if (_pending == null || _sending) return;
    await _ask();
  }

  Future<void> _ask() async {
    final question = _pending!;
    _sending = true;
    _error = null;
    _notify();
    try {
      final reply = await _repository.ask(question, _messages);
      _messages = [
        ..._messages,
        AssistantMessage.user(question),
        AssistantMessage.assistant(reply),
      ];
      _pending = null;
    } catch (error) {
      _error = error;
    } finally {
      _sending = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AssistantScope extends InheritedNotifier<AssistantController> {
  const AssistantScope({
    super.key,
    required AssistantController controller,
    required super.child,
  }) : super(notifier: controller);

  static AssistantController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AssistantScope>()!.notifier!;
}
