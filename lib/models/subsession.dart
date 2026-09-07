// Subsession model (parsed from the /subsessions endpoint snapshot).

/// A background subsession owned by a chat session — a one-shot task, a
/// periodic monitor, an event watcher, a user side-chat, or an on-close job.
///
/// Parsed from the ``subsession_id`` / ``kind`` / ``status`` / ... snapshot
/// dicts returned by ``GET /subsessions?session_id=...``.
class Subsession {
  final String subsessionId;
  final String kind;
  final String ownerSessionId;
  final String? parentId;
  final int? depth;
  final String title;
  final String? prompt;
  final int? modelLevel;
  final String status;
  final num? createdAt;
  final num? lastActivityAt;
  final num? intervalSeconds;
  final String? anchorTime;
  final num? nextRunAt;
  final int? runs;
  final int? maxRuns;
  final String? lastResult;
  final String? summary;
  final String? closeReason;
  final String? error;

  const Subsession({
    required this.subsessionId,
    this.kind = 'task',
    this.ownerSessionId = '',
    this.parentId,
    this.depth,
    this.title = '',
    this.prompt,
    this.modelLevel,
    this.status = 'unknown',
    this.createdAt,
    this.lastActivityAt,
    this.intervalSeconds,
    this.anchorTime,
    this.nextRunAt,
    this.runs,
    this.maxRuns,
    this.lastResult,
    this.summary,
    this.closeReason,
    this.error,
  });

  factory Subsession.fromJson(Map<String, dynamic> json) {
    return Subsession(
      subsessionId: json['subsession_id'] as String,
      kind: json['kind'] as String? ?? 'task',
      ownerSessionId: json['owner_session_id'] as String? ?? '',
      parentId: json['parent_id'] as String?,
      depth: json['depth'] as int?,
      title: json['title'] as String? ?? '',
      prompt: json['prompt'] as String?,
      modelLevel: json['model_level'] as int?,
      status: json['status'] as String? ?? 'unknown',
      createdAt: json['created_at'] as num?,
      lastActivityAt: json['last_activity_at'] as num?,
      intervalSeconds: json['interval_seconds'] as num?,
      anchorTime: json['anchor_time'] as String?,
      nextRunAt: json['next_run_at'] as num?,
      runs: json['runs'] as int?,
      maxRuns: json['max_runs'] as int?,
      lastResult: json['last_result'] as String?,
      summary: json['summary'] as String?,
      closeReason: json['close_reason'] as String?,
      error: json['error'] as String?,
    );
  }

  static const _activeStatuses = {
    'running',
    'waiting',
    'sleeping',
    'paused',
  };

  /// Whether this subsession still counts as live (not closed/failed/
  /// interrupted).
  bool get isActive => _activeStatuses.contains(status);

  /// Whether this is a recurring monitor (periodic) or an event watcher —
  /// the kinds users think of as "monitors".
  bool get isMonitor => kind == 'periodic' || kind == 'wait_for_event';
}
