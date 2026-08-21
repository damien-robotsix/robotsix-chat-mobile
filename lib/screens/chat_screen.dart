import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/update_service.dart';

/// Chat screen backed by [ApiService] with SSE streaming.
///
/// Provides session management (create, switch, close, delete) and
/// live SSE streaming for chat messages.  When switching sessions the
/// history is reloaded from the backend via [ApiService.getHistory]
/// and [ApiService.getEvents].
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

  // Session management
  List<ChatSession> _sessions = [];
  bool _sessionsLoading = false;
  String? _sessionsError;

  @override
  void initState() {
    super.initState();
    _initApiService();
    _checkForUpdate();
  }

  Future<void> _initApiService() async {
    try {
      final svc = await ApiService.fromStorage();
      setState(() => _apiService = svc);
      await _loadSessions();

      // If no token is present, prompt the user to log in via Settings.
      if (mounted) {
        final provider = ApiService.currentAuthProvider;
        if (provider is TokenExchangeAuthProvider) {
          final loggedIn = await provider.isLoggedIn;
          if (!loggedIn && mounted) {
            _showLoginPrompt();
          }
        }
      }
    } on StateError {
      // No base URL configured; API calls will fail gracefully.
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

  Future<void> _loadSessions() async {
    if (_apiService == null) return;
    setState(() {
      _sessionsLoading = true;
      _sessionsError = null;
    });
    try {
      final sessions = await _apiService!.listSessions();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _sessionsLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _sessionsError = e.toString();
          _sessionsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sessionsError = e.toString();
          _sessionsLoading = false;
        });
      }
    }
  }

  Future<void> _createSession() async {
    if (_apiService == null) return;
    try {
      final session = await _apiService!.createSession();
      await _loadSessions();
      await _switchToSession(session.sessionId);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create session: $e')),
        );
      }
    }
  }

  Future<void> _switchToSession(String sessionId) async {
    if (_apiService == null) return;
    _activeStream?.cancel();
    setState(() {
      _messages.clear();
      _sessionId = sessionId;
      _nextId = 0;
    });

    // Load history first, then reattach to live events.
    try {
      final history = await _apiService!.getHistory(sessionId);
      if (mounted) {
        final historyMessages = <ChatMessage>[];
        for (final entry in history) {
          final role = entry['role'] as String? ?? 'user';
          final content = entry['content'] as String? ?? '';
          historyMessages.add(ChatMessage(
            id: '${_nextId++}',
            text: content,
            isUser: role == 'user',
            timestamp: DateTime.now(),
          ));
        }
        setState(() => _messages.addAll(historyMessages));
      }
    } on Exception {
      // History load is best-effort — proceed with empty messages.
    }

    // Reattach SSE stream for live events.
    try {
      final stream = _apiService!.getEvents(sessionId);
      _activeStream = stream.listen(
        (event) {
          if (!mounted) return;
          switch (event) {
            case TokenEvent(:final content):
              setState(() {
                _appendToMessage('live-${_nextId}', content);
              });
            case DoneEvent():
              // Reattachment complete — ignore Done sentinel.
            case ErrorEvent(:final message, :final code):
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Event error [$code]: $message')),
                );
              }
          }
        },
        onError: (error) {
          // Stream error is non-fatal for reattachment.
        },
      );
    } on Exception {
      // Reattachment is best-effort.
    }
  }

  Future<void> _closeSession(String sessionId) async {
    if (_apiService == null) return;
    try {
      await _apiService!.closeSession(sessionId);
      if (_sessionId == sessionId) {
        setState(() => _sessionId = null);
      }
      await _loadSessions();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to close session: $e')),
        );
      }
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    if (_apiService == null) return;
    try {
      await _apiService!.deleteSession(sessionId);
      if (_sessionId == sessionId) {
        _activeStream?.cancel();
        setState(() {
          _sessionId = null;
          _messages.clear();
        });
      }
      await _loadSessions();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete session: $e')),
        );
      }
    }
  }

  void _showLoginPrompt() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Authentication Required'),
        content: const Text(
          'You need to log in via fleet SSO to use the chat. '
          'Open Settings to log in.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/settings');
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Chat send
  // ------------------------------------------------------------------

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
              _loadSessions(); // Refresh session list for new sessions.
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
      final msg = e.statusCode == 401
          ? 'Session expired. Please log in again via Settings.'
          : 'Server error: ${e.toString()}';
      setState(() {
        _updateMessage(agentMsgId, msg);
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

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('robotsix-chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment),
            tooltip: 'New session',
            onPressed: _createSession,
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Sessions',
            onPressed: () => _showSessionsDrawer(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Session indicator bar
          if (_sessionId != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'Session: ${_sessionId!.substring(0, _sessionId!.length < 8 ? _sessionId!.length : 8)}…',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
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

  void _showSessionsDrawer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sessions',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh',
                            onPressed: () async {
                              await _loadSessions();
                              setModalState(() {});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: 'New session',
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _createSession();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_sessionsLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_sessionsError != null)
                    Text(
                      _sessionsError!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    )
                  else if (_sessions.isEmpty)
                    const Text('No sessions yet.')
                  else
                    ..._sessions.map((s) {
                      final isActive = s.sessionId == _sessionId;
                      return ListTile(
                        leading: Icon(
                          isActive ? Icons.chat_bubble : Icons.chat_bubble_outline,
                          color: isActive
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          s.title ?? s.sessionId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: s.turnCount != null
                            ? Text('${s.turnCount} turns')
                            : null,
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            Navigator.pop(ctx);
                            switch (action) {
                              case 'close':
                                await _closeSession(s.sessionId);
                              case 'delete':
                                await _deleteSession(s.sessionId);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'close',
                              child: Text('Close'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (!isActive) {
                            _switchToSession(s.sessionId);
                          }
                        },
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }
}