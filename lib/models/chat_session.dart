// Session model (lightweight, parsed from JSON).

/// A chat session returned by GET /sessions.
class ChatSession {
  final String sessionId;
  final String? title;
  final int? turnCount;

  const ChatSession({
    required this.sessionId,
    this.title,
    this.turnCount,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      sessionId: json['session_id'] as String,
      title: json['title'] as String?,
      turnCount: json['turn_count'] as int?,
    );
  }
}
