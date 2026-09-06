// SSE events from the POST /chat stream.

/// Events emitted by the chat backend's SSE response stream.
sealed class ChatEvent {
  const ChatEvent();
}

/// A content token to append to the agent's reply in order.
class TokenEvent extends ChatEvent {
  final String content;
  const TokenEvent(this.content);
}

/// Terminal — the reply is complete.  Adopt [sessionId] for subsequent
/// messages (it may differ from the one you sent).
class DoneEvent extends ChatEvent {
  final String sessionId;
  final double timestamp;
  const DoneEvent({required this.sessionId, required this.timestamp});
}

/// Terminal — the backend rejected the request.
class ErrorEvent extends ChatEvent {
  final String message;
  final String code;
  final String? correlationId;
  const ErrorEvent({
    required this.message,
    required this.code,
    this.correlationId,
  });
}
