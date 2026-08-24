import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';

/// Convert a raw history entry (from `getHistory`) into a [ChatMessage].
ChatMessage _historyEntryToMessage(Map<String, dynamic> entry, int index) {
  final role = entry['role'] as String? ?? 'user';
  return ChatMessage(
    id: 'hist-$index',
    text: (entry['content'] as String?) ?? '',
    isUser: role == 'user',
    timestamp: DateTime.now(),
  );
}

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

  // Session drawer state
  List<ChatSession> _sessions = [];
  bool _isLoadingSessions = false;

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

  // ------------------------------------------------------------------
  // Session management
  // ------------------------------------------------------------------

  /// Load sessions from the API into the drawer.
  Future<void> _loadSessions() async {
    if (_isLoadingSessions) return;
    setState(() => _isLoadingSessions = true);
    try {
      _apiService ??= await ApiService.fromStorage();
      final sessions = await _apiService!.listSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _isLoadingSessions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingSessions = false);
    }
  }

  /// Create a new session and switch to it.
  Future<void> _createNewSession() async {
    try {
      _apiService ??= await ApiService.fromStorage();
      final session = await _apiService!.createSession();
      if (!mounted) return;
      setState(() {
        _sessionId = session.sessionId;
        _messages.clear();
        _nextId = 0;
      });
      Navigator.pop(context); // Close drawer
      await _loadSessions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create session: $e')),
      );
    }
  }

  /// Switch to an existing session, loading its history.
  Future<void> _switchToSession(ChatSession session) async {
    Navigator.pop(context); // Close drawer
    setState(() {
      _sessionId = session.sessionId;
      _messages.clear();
      _nextId = 0;
      _isLoading = true;
    });
    try {
      _apiService ??= await ApiService.fromStorage();
      final history = await _apiService!.getHistory(session.sessionId);
      if (!mounted) return;
      setState(() {
        _messages.addAll(
          history.asMap().entries.map(
                (e) => _historyEntryToMessage(e.value, e.key),
              ),
        );
        _nextId = history.length;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  /// Delete a session and refresh the list.
  Future<void> _deleteSession(ChatSession session) async {
    try {
      _apiService ??= await ApiService.fromStorage();
      await _apiService!.deleteSession(session.sessionId);
      if (!mounted) return;
      if (_sessionId == session.sessionId) {
        setState(() {
          _sessionId = null;
          _messages.clear();
          _nextId = 0;
        });
      }
      await _loadSessions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete session: $e')),
      );
    }
  }

  /// Close a session and refresh the list.
  Future<void> _closeSession(ChatSession session) async {
    try {
      _apiService ??= await ApiService.fromStorage();
      await _apiService!.closeSession(session.sessionId);
      if (!mounted) return;
      await _loadSessions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session closed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to close session: $e')),
      );
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
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Sessions',
            onPressed: () {
              Scaffold.of(context).openDrawer();
              _loadSessions();
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Sessions',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _createNewSession,
                      icon: const Icon(Icons.add),
                      label: const Text('New Chat'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _isLoadingSessions
                    ? const Center(child: CircularProgressIndicator())
                    : _sessions.isEmpty
                        ? const Center(
                            child: Text(
                              'No sessions yet.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _sessions.length,
                            itemBuilder: (context, index) {
                              final session = _sessions[index];
                              final isActive =
                                  session.sessionId == _sessionId;
                              return ListTile(
                                key: ValueKey(session.sessionId),
                                selected: isActive,
                                leading: Icon(
                                  isActive
                                      ? Icons.chat_bubble
                                      : Icons.chat_bubble_outline,
                                ),
                                title: Text(
                                  session.title ??
                                      'Session ${session.sessionId}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: session.turnCount != null
                                    ? Text('${session.turnCount} turns')
                                    : null,
                                trailing: PopupMenuButton<String>(
                                  key: ValueKey(
                                      'menu_${session.sessionId}'),
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'close':
                                        _closeSession(session);
                                      case 'delete':
                                        _deleteSession(session);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'close',
                                      child: Text('Close session'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete session'),
                                    ),
                                  ],
                                ),
                                onTap: () => _switchToSession(session),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
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
