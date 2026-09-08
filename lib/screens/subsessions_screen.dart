import 'package:flutter/material.dart';

import '../models/api_exception.dart';
import '../models/chat_session.dart';
import '../models/subsession.dart';
import '../services/api_service.dart';

/// A row in the subsessions list: a [Subsession] plus the title of the
/// chat session that owns it, so the user can tell where each monitor
/// belongs.
class _SubsessionRow {
  final Subsession subsession;
  final String parentTitle;

  const _SubsessionRow(this.subsession, this.parentTitle);
}

/// Read-only view of the background subsessions (tasks, periodic
/// monitors, event watchers, side-chats) owned by the current user's
/// chat sessions.
class SubsessionsScreen extends StatefulWidget {
  const SubsessionsScreen({super.key});

  @override
  State<SubsessionsScreen> createState() => _SubsessionsScreenState();
}

class _SubsessionsScreenState extends State<SubsessionsScreen> {
  ApiService? _apiService;
  bool _loading = true;
  String? _error;
  List<_SubsessionRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _apiService ??= await ApiService.fromStorage();
    } on StateError {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No backend configured. Open Settings first.';
        });
      }
      return;
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    final api = _apiService;
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sessions = await api.listSessions();
      final perSession = await Future.wait(
        sessions.map((s) => _listSubsessions(api, s)),
      );

      final rows = <_SubsessionRow>[];
      for (var i = 0; i < sessions.length; i++) {
        final parentTitle = sessions[i].title ?? sessions[i].sessionId;
        for (final sub in perSession[i]) {
          rows.add(_SubsessionRow(sub, parentTitle));
        }
      }
      rows.sort((a, b) {
        final aTs = a.subsession.lastActivityAt ?? 0;
        final bTs = b.subsession.lastActivityAt ?? 0;
        return bTs.compareTo(aTs);
      });

      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } on AuthException {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Session expired — log in again from Settings.';
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  /// List one session's subsessions, swallowing per-session failures so a
  /// single broken session never blanks the whole view.
  Future<List<Subsession>> _listSubsessions(
    ApiService api,
    ChatSession session,
  ) async {
    try {
      return await api.listSubsessions(session.sessionId);
    } catch (_) {
      return const <Subsession>[];
    }
  }

  Future<void> _closeSubsession(Subsession sub) async {
    final api = _apiService;
    if (api == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close subsession?'),
        content: Text(
          'This cancels the background work of "${sub.title}". '
          'Its final summary will still be delivered to its parent chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await api.closeSubsession(sub.subsessionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Closed "${sub.title}"')),
        );
        await _refresh();
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Close failed: ${e.message}')),
        );
      }
    }
  }

  void _showDetails(_SubsessionRow row) {
    final sub = row.subsession;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              sub.title.isEmpty
                  ? _shortId(sub.subsessionId)
                  : sub.title,
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${_kindLabel(sub.kind)} · ${sub.status} · '
              'owner: ${row.parentTitle}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            _detailLine(ctx, 'Kind', _kindLabel(sub.kind)),
            _detailLine(ctx, 'Status', sub.status),
            _detailLine(
              ctx,
              'Runs',
              '${sub.runs ?? 0}'
              '${sub.maxRuns != null ? ' / ${sub.maxRuns}' : ''}',
            ),
            if (sub.intervalSeconds != null)
              _detailLine(
                ctx,
                'Interval',
                _formatInterval(sub.intervalSeconds!),
              ),
            if (sub.nextRunAt != null)
              _detailLine(ctx, 'Next run', _formatFuture(sub.nextRunAt!)),
            _detailLine(
              ctx,
              'Last activity',
              _formatPast(sub.lastActivityAt),
            ),
            if (sub.modelLevel != null)
              _detailLine(ctx, 'Model level', '${sub.modelLevel}'),
            if (sub.summary != null && sub.summary!.isNotEmpty)
              _detailBlock(ctx, 'Summary', sub.summary!),
            if (sub.lastResult != null && sub.lastResult!.isNotEmpty)
              _detailBlock(ctx, 'Last result', sub.lastResult!),
            if (sub.error != null && sub.error!.isNotEmpty)
              _detailBlock(ctx, 'Error', sub.error!),
            if (sub.closeReason != null && sub.closeReason!.isNotEmpty)
              _detailLine(ctx, 'Close reason', sub.closeReason!),
          ],
        ),
      ),
    );
  }

  Widget _detailLine(BuildContext ctx, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(ctx).textTheme.labelMedium),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _detailBlock(BuildContext ctx, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(ctx).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _rows.where((r) => r.subsession.isActive).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subsessions & Monitors'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(activeCount),
      ),
    );
  }

  Widget _buildBody(int activeCount) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Failed to load subsessions',
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_rows.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(48),
            child: Center(
              child: Text(
                'No subsessions yet.\n'
                'Background tasks and monitors you start in chat will '
                'appear here.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '${_rows.length} subsession${_rows.length == 1 ? '' : 's'} · '
            '$activeCount active',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        for (final row in _rows) _buildTile(row),
      ],
    );
  }

  Widget _buildTile(_SubsessionRow row) {
    final sub = row.subsession;
    return ListTile(
      leading: Icon(_kindIcon(sub.kind)),
      title: Text(
        sub.title.isEmpty ? _shortId(sub.subsessionId) : sub.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_kindLabel(sub.kind)} · ${sub.status} · '
        '${row.parentTitle}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) {
          if (action == 'details') {
            _showDetails(row);
          } else if (action == 'close' && sub.isActive) {
            _closeSubsession(sub);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'details',
            child: Text('Details'),
          ),
          if (sub.isActive)
            const PopupMenuItem(
              value: 'close',
              child: Text('Close', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      onTap: () => _showDetails(row),
    );
  }
}

String _shortId(String id) =>
    id.length > 12 ? '${id.substring(0, 12)}…' : id;

IconData _kindIcon(String kind) {
  switch (kind) {
    case 'periodic':
      return Icons.schedule;
    case 'wait_for_event':
      return Icons.event;
    case 'user_chat':
      return Icons.forum;
    case 'on_close':
      return Icons.exit_to_app;
    case 'evergoing':
    case 'root':
    case 'parent':
      return Icons.layers;
    case 'task':
    default:
      return Icons.task_alt;
  }
}

String _kindLabel(String kind) {
  switch (kind) {
    case 'periodic':
      return 'Monitor';
    case 'wait_for_event':
      return 'Event watcher';
    case 'user_chat':
      return 'Side-chat';
    case 'on_close':
      return 'On-close task';
    case 'evergoing':
    case 'root':
    case 'parent':
      return 'Evergoing';
    case 'task':
    default:
      return 'Task';
  }
}

String _formatInterval(num seconds) {
  final s = seconds.round();
  if (s < 60) return '$s s';
  if (s < 3600) return '${s ~/ 60} min';
  return '${(s / 3600).toStringAsFixed(1)} h';
}

String _formatPast(num? ts) {
  if (ts == null) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(
    (ts * 1000).round(),
    isUtc: true,
  );
  final diff = DateTime.now().toUtc().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

String _formatFuture(num? ts) {
  if (ts == null) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(
    (ts * 1000).round(),
    isUtc: true,
  ).toLocal();
  final diff = dt.difference(DateTime.now());
  if (diff.isNegative) return 'due';
  if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'in ${diff.inHours} h';
  return 'in ${diff.inDays} d';
}
