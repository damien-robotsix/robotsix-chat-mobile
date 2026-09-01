import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/update_service.dart';

/// Chat screen backed by [ApiService] with SSE streaming and
/// session management.
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

  // Session management state
  List<ChatSession> _sessions = [];
  bool _sessionsLoading = false;
  String? _sessionsError;

  StreamSubscription<bool>? _authSub;

  @override
  void initState() {
    super.initState();
    _initApiService();
    // Re-initialise the API client whenever auth state becomes true (e.g.
    // after SSO login), so the chat screen stops using a stale token-less
    // client built before login.
    _authSub =
        OidcTokenExchangeAuthProvider.authStateChanges.listen((isLoggedIn) {
      if (isLoggedIn && mounted) {
        _initApiService();
      }
    });
    _checkForUpdate();
  }

  Future<void> _initApiService() async {
    try {
      _apiService = await ApiService.fromStorage();
      if (mounted) _loadSessions();
    } on StateError {
      // No base URL configured; API calls will fail gracefully
      // with a helpful error message.
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
      final list = await _apiService!.listSessions();
      if (mounted) {
        setState(() {
          _sessions = list;
          _sessionsLoading = false;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _sessionsError = e.message;
          _sessionsLoading = false;
        });
        _showReLoginPrompt();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _sessionsError = e.message;
          _sessionsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sessionsError = '$e';
          _sessionsLoading = false;
        });
      }
    }
  }

  Future<void> _createSession() async {
    if (_apiService == null) return;
    try {
      final session = await _apiService!.createSession();
      if (mounted) {
        _switchToSession(session.sessionId);
        _loadSessions();
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        _showReLoginPrompt();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Create session failed: ${e.message}')),
        );
      }
    }
  }

  Future<void> _switchToSession(String sessionId) async {
    if (_apiService == null) return;
    setState(() {
      _sessionId = sessionId;
      _messages.clear();
      _isLoading = true;
    });
    try {
      final history = await _apiService!.getHistory(sessionId);
      if (mounted) {
        setState(() {
          _messages.clear();
          for (final entry in history) {
            final role = entry['role'] as String? ?? 'user';
            final content = entry['content'] as String? ?? '';
            _messages.add(ChatMessage(
              id: '${_nextId++}',
              text: content,
              isUser: role == 'user',
              timestamp: DateTime.now(),
            ));
          }
          _isLoading = false;
        });
      }
    } on AuthException {
      if (mounted) {
        setState(() {
          _messages.clear();
          _isLoading = false;
        });
        _showReLoginPrompt();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _messages.clear();
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('History load failed: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    if (_apiService == null) return;
    try {
      await _apiService!.deleteSession(sessionId);
      if (_sessionId == sessionId) {
        setState(() {
          _sessionId = null;
          _messages.clear();
        });
      }
      _loadSessions();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        _showReLoginPrompt();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete session failed: ${e.message}')),
        );
      }
    }
  }

  Future<void> _closeSession(String sessionId) async {
    if (_apiService == null) return;
    try {
      await _apiService!.closeSession(sessionId);
      _loadSessions();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        _showReLoginPrompt();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Close session failed: ${e.message}')),
        );
      }
    }
  }

  // ------------------------------------------------------------------
  // Chat
  // ------------------------------------------------------------------

  /// Show a dialog prompting the user to re-authenticate after their
  /// session has expired.
  void _showReLoginPrompt() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Expired'),
        content: const Text(
          'Your login session has expired. '
          'Would you like to go to Settings to log in again?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openSettings();
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  /// Open Settings and refresh auth state afterwards, so a login that
  /// completed while Settings was open is picked up immediately.
  Future<void> _openSettings() async {
    await Navigator.pushNamed(context, '/settings');
    if (mounted) _initApiService();
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
    _authSub?.cancel();
    _activeStream?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleStreamError(String agentMsgId, String errorMsg) {
    if (!mounted) return;
    setState(() {
      _updateMessage(agentMsgId, errorMsg);
      _isLoading = false;
    });
    _activeStream = null;
  }

  void _onStreamEvent(ChatEvent event, String agentMsgId) {
    if (!mounted) return;
    switch (event) {
      case TokenEvent(:final content):
        setState(() => _appendToMessage(agentMsgId, content));
      case DoneEvent(:final sessionId):
        setState(() {
          _sessionId = sessionId;
          _isLoading = false;
        });
        _activeStream = null;
        _loadSessions();
      case ErrorEvent(:final message, :final code):
        _handleStreamError(agentMsgId, 'Error [$code]: $message');
    }
  }

  StreamSubscription<ChatEvent> _subscribeToStream(
      Stream<ChatEvent> stream, String agentMsgId) {
    return stream.listen(
      (event) => _onStreamEvent(event, agentMsgId),
      onError: (error) =>
          _handleStreamError(agentMsgId, 'Stream error: $error'),
      onDone: () {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _activeStream = null;
      },
    );
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

      _activeStream = _subscribeToStream(stream, agentMsgId);
    } on AuthException catch (e) {
      _handleStreamError(agentMsgId, e.message);
      _showReLoginPrompt();
    } on ApiException catch (e) {
      _handleStreamError(agentMsgId, 'Server error: ${e.toString()}');
    } on StateError catch (e) {
      _handleStreamError(agentMsgId, e.message);
    } catch (e) {
      _handleStreamError(agentMsgId, 'Network error: $e');
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
            onPressed: _openSettings,
          ),
        ],
      ),
      drawer: _buildSessionDrawer(),
      body: Column(
        children: [
          // Session indicator bar
          _buildSessionBar(),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet.\nType below to start chatting.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return ListTile(
                        title: Align(
                          alignment: msg.isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.all(12),
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
                        ),
                      );
                    },
                  ),
          ),
          // Input bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _isLoading ? null : _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionBar() {
    final label = _sessionId != null
        ? 'Session: ${_sessionId!.length > 12 ? _sessionId!.substring(0, 12) : _sessionId}...'
        : 'No session';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            _sessionId != null ? Icons.chat_bubble : Icons.chat_bubble_outline,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New session',
            onPressed: _createSession,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSessionDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 12),
                  Text(
                    'Sessions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'New session',
                    onPressed: () {
                      Navigator.pop(context); // close drawer
                      _createSession();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _sessionsLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _sessionsError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Failed to load sessions',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _sessionsError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _loadSessions,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _sessions.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('No sessions yet.'),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _createSession();
                                    },
                                    icon: const Icon(Icons.add),
                                    label: const Text('Create one'),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _sessions.length,
                              itemBuilder: (context, index) {
                                final session = _sessions[index];
                                final isActive =
                                    session.sessionId == _sessionId;
                                return ListTile(
                                  selected: isActive,
                                  leading: Icon(
                                    isActive
                                        ? Icons.chat_bubble
                                        : Icons.chat_bubble_outline,
                                  ),
                                  title: Text(
                                    session.title ??
                                        '${session.sessionId.length > 16 ? session.sessionId.substring(0, 16) : session.sessionId}...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: session.turnCount != null
                                      ? Text('${session.turnCount} turns')
                                      : null,
                                  onTap: () {
                                    Navigator.pop(context);
                                    if (!isActive) {
                                      _switchToSession(session.sessionId);
                                    }
                                  },
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (action) {
                                      if (action == 'delete') {
                                        _deleteSession(session.sessionId);
                                      } else if (action == 'close') {
                                        _closeSession(session.sessionId);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'close',
                                        child: Text('Close'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
