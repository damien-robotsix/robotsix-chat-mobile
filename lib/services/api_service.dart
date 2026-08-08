import 'dart:async';

/// Stub API service for robotsix-chat backend.
///
/// TODO: Replace with real HTTP calls to the backend.
/// TODO: Add SSE streaming for real-time agent messages.
/// TODO: Add authentication (token management, refresh).
class ApiService {
  /// Base URL of the robotsix-chat backend (e.g. https://chat.example.com).
  final String baseUrl;

  /// Authentication token for the backend.
  final String? token;

  const ApiService({required this.baseUrl, this.token});

  /// Send a chat message and receive the agent's response.
  ///
  /// Currently returns a stubbed reply after a short delay to simulate
  /// network latency.  Replace with a real POST + SSE stream.
  Future<String> sendMessage(String message) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return '[stub] Agent response to: "$message"';
  }

  /// Connect to the SSE event stream for real-time agent messages.
  ///
  /// Not yet implemented — will use [baseUrl] + auth [token].
  Stream<String> messageStream() async* {
    // TODO: implement SSE client
    yield '[stub] SSE stream connected';
  }
}
