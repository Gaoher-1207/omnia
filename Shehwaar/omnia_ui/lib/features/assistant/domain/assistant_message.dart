enum AssistantRole { user, assistant }

/// One turn of an Ask Omnia conversation. Plain text only: replies are shown
/// as text, never interpreted as markup or links.
class AssistantMessage {
  const AssistantMessage(this.role, this.text);
  const AssistantMessage.user(this.text) : role = AssistantRole.user;
  const AssistantMessage.assistant(this.text) : role = AssistantRole.assistant;

  final AssistantRole role;
  final String text;

  bool get fromUser => role == AssistantRole.user;
}
