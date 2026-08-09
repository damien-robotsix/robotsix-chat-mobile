import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';

/// Chat screen backed by [ApiService] with SSE streaming.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _controller = TextEditingController();
  int _nextId = 0;
  ApiService? _apiService;
  bool _isLoading = false;
  String? _sessionId;
  StreamSubscription<ChatEvent>? _activeStream;

  @override
  void initState() {
    super.initState();
    _initApiService();
    _checkForUpdate();
  }

  Future<void> _initApiService() async {
    try {
      _apiService = await ApiService.fromStorage();
    } on StateError {
      // No base URL configured; API calls will fail gracefully
      // with a helpful error message.
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final result = await UpdateService().checkForUpdate();
      if (!mounted) return;
      if (result.status == UpdateStatus.updateAvailable) {
        showUpdateDialog(context, result);
      }
    } on Exception {
      // Update check is non-critical; silently ignore failures.
    }
  }

  @override
  void dispose() {
    _activeStream?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _messages.add(ChatMessage(
        id: '${_nextId++}',
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _controller.clear();
      _isLoading = true;
    });

    final agentMsgId = '${_nextId++}';
    setState(() {
      _messages.add(ChatMessage(
        id: agentMsgId,
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });

    try {
      _apiService ??= await ApiService.fromStorage();

      final stream = _apiService!.sendMessage(
        message: text,
        sessionId: _sessionId,
        messageId: agentMsgId,
      );

      _activeStream = stream.listen(
        (event) {
          if (!mounted) return;
          switch (event) {
            case TokenEvent(:final content):
              setState(() {
                _appendToMessage(agentMsgId, content);
              });
            case DoneEvent(:final sessionId):
              setState(() {
                _sessionId = sessionId;
                _isLoading = false;
              });
              _activeStream = null;
            case ErrorEvent(:final message, :final code):
              setState(() {
                _updateMessage(
                    agentMsgId, 'Error [$code]: $message');
                _isLoading = false;
              });
              _activeStream = null;
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _updateMessage(agentMsgId, 'Stream error: $error');
            _isLoading = false;
          });
          _activeStream = null;
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
          });
          _activeStream = null;
        },
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _updateMessage(agentMsgId, 'Server error: ${e.toString()}');
        _isLoading = false;
      });
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _updateMessage(agentMsgId, e.message);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updateMessage(agentMsgId, 'Network error: $e');
        _isLoading = false;
      });
    }
  }

  void _appendToMessage(String id, String text) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx != -1) {
      final current = _messages[idx];
      _messages[idx] = ChatMessage(
        id: id,
        text: current.text + text,
        isUser: false,
        timestamp: current.timestamp,
      );
    }
  }

  void _updateMessage(String id, String text) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx != -1) {
      _messages[idx] = ChatMessage(
        id: id,
        text: text,
        isUser: false,
        timestamp: _messages[idx].timestamp,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('robotsix-chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet.\nType below to start chatting.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return Align(
                        alignment: msg.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: msg.isUser
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(msg.text),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type a message…',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton.filled(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
